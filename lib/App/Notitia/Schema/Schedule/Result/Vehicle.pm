package App::Notitia::Schema::Schedule::Result::Vehicle;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string },
             '+'  => sub { $_[ 0 ]->_as_number }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( VARCHAR_MAX_SIZE );
use App::Notitia::Util      qw( date_data_type foreign_key_data_type
                                nullable_foreign_key_data_type
                                serial_data_type varchar_data_type );
use Class::Usul::Functions  qw( throw );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

my $left_join = { join_type => 'left' };

$class->table( 'vehicle' );

$class->add_columns
   ( id       => serial_data_type,
     type_id  => foreign_key_data_type,
     owner_id => nullable_foreign_key_data_type,
     aquired  => date_data_type,
     disposed => date_data_type,
     vrn      => varchar_data_type( 16 ),
     name     => varchar_data_type( 64 ),
     notes    => varchar_data_type, );

$class->set_primary_key( 'id' );

$class->add_unique_constraint( [ 'vrn' ] );

$class->belongs_to( owner => "${result}::Person", 'owner_id', $left_join );
$class->belongs_to( type  => "${result}::Type", 'type_id' );

# Private methods
sub _as_number {
   return $_[ 0 ]->id;
}

sub _as_string {
   return $_[ 0 ]->vrn;
}

my $_assert_event_assignment_allowed = sub {
   my ($self, $event, $assigner) = @_;

   $assigner->assert_member_of( 'asset_manager' );

   my $schema     = $self->result_source->schema;
   my $dtp        = $schema->storage->datetime_parser;
   my $event_date = $dtp->format_datetime( $event->rota->date );
   my $event_rs   = $schema->resultset( 'Event' );
   my $rota_rs    = $schema->resultset( 'Rota'  );

   for my $rota ($rota_rs->search( { date    => $event_date },
                                   { columns => [ 'id' ]    } )) {
      for my $other ($event_rs->search( { rota_id  => $rota->id },
                                        { prefetch => 'transports' } )) {
         for my $transport ($other->transports) {
            $transport->vehicle_id != $self->id and next;

            $transport->event_id == $event->id
               and throw 'Vehicle [_1] already assigned to this event',
                         [ $self ], level => 2;
            # TODO: Test for overlapping times
            throw 'Vehicle [_1] already assigned to event [_2]',
                  [ $self, $event ], level => 2;
         }
      }
   }

   return;
};

my $_assert_public_or_private = sub {
   my $self = shift;

   $self->name and $self->owner_id and throw
      'Cannot set name and owner', level => 2, rv => HTTP_EXPECTATION_FAILED;

   return;
};

my $_find_rota_type_id_for = sub {
   my ($self, $name) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Type' )->find_rota_by( $name )->id;
};

my $_assert_slot_assignment_allowed = sub {
   my ($self, $rota_name, $date, $shift_type, $slot_type, $person, $bike) = @_;

   $person->assert_member_of( 'asset_manager' );

   $slot_type eq 'rider' and $bike and $self->type ne 'bike'
      and throw 'Vehicle [_1] is not a bike and one was requested', [ $self ];

   if ($slot_type eq 'rider') {
      my $schema  = $self->result_source->schema;
      my $type_id = $self->$_find_rota_type_id_for( $rota_name );
      my $slots   = $schema->resultset( 'Slot' )->search
         ( { 'rota.type_id' => $type_id, 'rota.date' => $date },
           { columns  => [ qw( shift.type me.type subslot
                               vehicle.name vehicle.vrn ) ],
             join     => [ { 'shift' => 'rota' }, 'vehicle', ],
             prefetch => [ { 'shift' => 'rota' }, 'vehicle', ] } );

      for my $slot (grep { $_->type eq 'rider' } $slots->all) {
         $slot->shift->type eq $shift_type
            and $slot->vehicle and $slot->vehicle->vrn eq $self->vrn
            and throw 'Vehicle [_1] already assigned to slot [_2]',
                      [ $self, $slot->subslot ], level => 2,
                      rv => HTTP_EXPECTATION_FAILED;
      }
   }

   return;
};

my $_find_assigner = sub {
   my ($self, $name) = @_; my $schema = $self->result_source->schema;

   return $schema->resultset( 'Person' )->find_person_by( $name );
};

my $_find_slot = sub {
   my ($self, $rota_name, $date, $shift_type, $slot_type, $subslot) = @_;

   my $shift = $self->find_shift( $rota_name, $date, $shift_type );
   my $slot  = $self->find_slot( $shift, $slot_type, $subslot );

   $slot or throw 'Slot [_1] has not been claimed', [ $slot ];

   return $slot;
};

# Public methods
sub assign_to_event {
   my ($self, $event_name, $assigner_name) = @_;

   my $schema   = $self->result_source->schema;
   my $event_rs = $schema->resultset( 'Event' );
   my $event    = $event_rs->search
      ( { name => $event_name }, { prefetch => 'rota' } )->single
      or throw 'Event [_1] is unknown', [ $event_name ];
   my $assigner = $self->$_find_assigner( $assigner_name );

   $self->$_assert_event_assignment_allowed( $event, $assigner );

   return $schema->resultset( 'Transport' )->create
      ( { event_id => $event->id, vehicle_id => $self->id,
          vehicle_assigner_id => $assigner->id } );
}

sub assign_slot {
   my ($self, $rota_name, $date, $shift_type, $slot_type, $subslot, $name) = @_;

   my $slot   = $self->$_find_slot
      ( $rota_name, $date, $shift_type, $slot_type, $subslot );
   my $person = $self->$_find_assigner( $name );
   my $bike   = $slot->bike_requested;

   $self->$_assert_slot_assignment_allowed
      ( $rota_name, $date, $shift_type, $slot_type, $person, $bike );

   $slot->vehicle_id( $self->id ); $slot->vehicle_assigner_id( $person->id );

   return $slot->update;
}

sub insert {
   my $self = shift;

   App::Notitia->env_var( 'bulk_insert' ) or $self->validate;

   $self->$_assert_public_or_private();

   return $self->next::method;
}

sub label {
   return $_[ 0 ]->name  ? $_[ 0 ]->vrn.' ('.$_[ 0 ]->name.')'
        : $_[ 0 ]->owner ? $_[ 0 ]->vrn.' ('.$_[ 0 ]->owner.')'
                         : $_[ 0 ]->vrn;
}

sub slotref {
   return $_[ 0 ]->name ? $_[ 0 ]->name : $_[ 0 ]->vrn;
}

sub unassign_slot {
   my ($self, $rota_name, $date, $shift_type, $slot_type, $subslot, $name) = @_;

   my $slot = $self->$_find_slot
      ( $rota_name, $date, $shift_type, $slot_type, $subslot );

   $slot->vehicle_id( undef ); $slot->vehicle_assigner_id( undef );

   return $slot->update;
}

sub update {
   my ($self, $columns) = @_;

   $columns and $self->set_inflated_columns( $columns ); $self->validate;

   $self->$_assert_public_or_private();

   return $self->next::method;
}

sub validation_attributes {
   return { # Keys: constraints, fields, and filters (all hashes)
      constraints      => {
         name          => { max_length => 64, min_length => 3, },
         notes         => { max_length => VARCHAR_MAX_SIZE(), min_length => 0 },
         vrn           => { max_length => 16, min_length => 3, },
      },
      fields           => {
         aquired       => { validate => 'isValidDate' },
         disposed      => { validate => 'isValidDate' },
         name          => { validate => 'isValidLength isValidIdentifier' },
         notes         => { validate => 'isValidLength isValidText' },
         vrn           => {
            validate   => 'isMandatory isValidLength isValidIdentifier' },
      },
      level => 8,
   };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Vehicle - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Vehicle;
   # Brief but working code examples

=head1 Description

=head1 Configuration and Environment

Defines the following attributes;

=over 3

=back

=head1 Subroutines/Methods

=head1 Diagnostics

=head1 Dependencies

=over 3

=item L<Class::Usul>

=back

=head1 Incompatibilities

There are no known incompatibilities in this module

=head1 Bugs and Limitations

There are no known bugs in this module. Please report problems to
http://rt.cpan.org/NoAuth/Bugs.html?Dist=App-Notitia.
Patches are welcome

=head1 Acknowledgements

Larry Wall - For the Perl programming language

=head1 Author

Peter Flanigan, C<< <pjfl@cpan.org> >>

=head1 License and Copyright

Copyright (c) 2016 Peter Flanigan. All rights reserved

This program is free software; you can redistribute it and/or modify it
under the same terms as Perl itself. See L<perlartistic>

This program is distributed in the hope that it will be useful,
but WITHOUT WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE

=cut

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
