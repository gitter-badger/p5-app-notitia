package App::Notitia::Schema::Schedule::ResultSet::Slot;

use strictures;
use parent 'DBIx::Class::ResultSet';

use App::Notitia::Constants qw( FALSE NUL TRUE );
use Class::Usul::Functions  qw( throw );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );

# Public methods
sub assignment_slots {
   my ($self, $type_id, $date) = @_;

   return $self->search
      ( { 'rota.type_id' => $type_id, 'rota.date' => $date },
        { 'columns' => [ $self->me( 'type_name' ), 'subslot' ],
          'join'    => [ { 'shift' => 'rota' }, 'vehicle', ],
          '+select' => [ 'shift.type_name', 'vehicle.name', 'vehicle.vrn' ],
          '+as'     => [ 'shift_type', 'vehicle_name', 'vehicle_vrn' ] } );
}

sub find_slot_by {
   my ($self, $shift, $slot_type, $subslot) = @_;

   return $self->find( { shift_id => $shift->id, type_name => $slot_type,
                         subslot  => $subslot } );
}

sub search_for_assigned_slots {
   my ($self, $opts) = @_; $opts = { %{ $opts } };

   my $where  = { 'vehicle.vrn' => delete $opts->{vehicle} };
   my $parser = $self->result_source->schema->datetime_parser;
   my $after  = delete $opts->{after}; my $before = delete $opts->{before};

   if ($after) {
      $where->{ 'rota.date' } =
              { '>' => $parser->format_datetime( $after ) };
      $opts->{order_by} //= 'date';
   }
   elsif ($before) {
      $where->{ 'rota.date' } =
              { '<' => $parser->format_datetime( $before ) };
   }

   my $prefetch = [ 'vehicle', { 'shift' => { 'rota' => 'type' } } ];

   $opts->{order_by} //= { -desc => 'date' };

   return $self->search( $where, { prefetch => $prefetch, %{ $opts } } );
}

sub list_slots_for {
   my ($self, $type_id, $date) = @_;

   my $attr = [ 'operator.first_name', 'operator.id', 'operator.last_name',
                'operator.name', 'vehicle.name', 'vehicle.vrn' ];

   return $self->search
      ( { 'rota.type_id' => $type_id, 'rota.date' => $date },
        { 'columns'  => [ qw( bike_requested type_name subslot ) ],
          'join'     => [ 'operator', 'vehicle' ],
          'prefetch' => [ { 'shift' => 'rota' }, 'operator_vehicles' ],
          '+select'  => $attr,
          '+as'      => $attr, } );
}

sub me {
   return join '.', $_[ 0 ]->current_source_alias, $_[ 1 ] // NUL;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::ResultSet::Slot - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::ResultSet::Slot;
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
