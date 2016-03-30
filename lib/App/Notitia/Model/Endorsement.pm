package App::Notitia::Model::Endorsement;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL TRUE );
use App::Notitia::Util      qw( admin_navigation_links bind bind_fields
                                check_field_server delete_button
                                loc management_link register_action_paths
                                save_button uri_for_action );
use Class::Null;
use Class::Usul::Functions  qw( is_member throw );
use Class::Usul::Time       qw( time2str );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'blots';

register_action_paths
   'blots/endorsement'  => 'endorsement',
   'blots/endorsements' => 'endorsements';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash = $orig->( $self, $req, @args );

   $stash->{nav }->{list    } = admin_navigation_links $req;
   $stash->{page}->{location} = 'admin';

   return $stash;
};

# Private class attributes
my $_blots_links_cache = {};

# Private functions
my $_add_endorsement_button = sub {
   my ($req, $action, $name) = @_;

   return { class => 'fade',
            hint  => loc( $req, 'Hint' ),
            href  => uri_for_action( $req, $action, [ $name ] ),
            name  => 'add_blot',
            tip   => loc( $req, 'add_blot_tip', [ 'endorsement', $name ] ),
            type  => 'link',
            value => loc( $req, 'add_blot' ) };
};

my $_endorsements_headers = sub {
   my $req = shift;

   return [ map { { value => loc( $req, "blots_heading_${_}" ) } } 0 .. 1 ];
};

# Private methods
my $_add_endorsement_js = sub {
   my $self = shift;
   my $opts = { domain => 'schedule', form => 'Endorsement' };

   return [ check_field_server( 'type_code', $opts ),
            check_field_server( 'endorsed',  $opts ), ];
};

my $_endorsement_links = sub {
   my ($self, $req, $name, $uri) = @_;

   my $links = $_blots_links_cache->{ $uri }; $links and return @{ $links };

   my $opts = { args => [ $name, $uri ] }; $links = [];

   for my $actionp (map { $self->moniker."/${_}" } 'endorsement' ) {
      push @{ $links }, {
         value => management_link( $req, $actionp, $name, $opts ) };
   }

   $_blots_links_cache->{ $uri } = $links;

   return @{ $links };
};

# Private methods
my $_bind_endorsement_fields = sub {
   my ($self, $blot) = @_;

   my $map      =  {
      type_code => { class => 'standard-field server' },
      endorsed  => { class => 'standard-field server' },
      notes     => { class => 'standard-field autosize' },
      points    => {},
   };

   return bind_fields $self->schema, $blot, $map, 'Endorsement';
};

my $_find_endorsement_by = sub {
   my ($self, @args) = @_; my $schema = $self->schema;

   return $schema->resultset( 'Endorsement' )->find_endorsement_by( @args );
};

my $_maybe_find_endorsement = sub {
   return $_[ 2 ] ? $_[ 0 ]->$_find_endorsement_by( $_[ 1 ], $_[ 2 ] )
                  : Class::Null->new;
};

my $_update_endorsement_from_request = sub {
   my ($self, $req, $blot) = @_;

   my $params = $req->body_params; my $opts = { optional => TRUE };

   for my $attr (qw( type_code endorsed notes points )) {
      if (is_member $attr, [ 'notes' ]) { $opts->{raw} = TRUE }
      else { delete $opts->{raw} }

      my $v = $params->( $attr, $opts );

      defined $v or next; $v =~ s{ \r\n }{\n}gmx; $v =~ s{ \r }{\n}gmx;

      length $v and is_member $attr, [ 'endorsed' ]
         and $v = $self->local_dt( $v );

      $blot->$attr( $v );
   }

   return;
};

# Public functions
sub endorsement : Role(person_manager) {
   my ($self, $req) = @_;

   my $name       =  $req->uri_params->( 0 );
   my $uri        =  $req->uri_params->( 1, { optional => TRUE } );
   my $blot       =  $self->$_maybe_find_endorsement( $name, $uri );
   my $page       =  {
      fields      => $self->$_bind_endorsement_fields( $blot ),
      first_field => $uri ? 'endorsed' : 'type_code',
      literal_js  => $self->$_add_endorsement_js(),
      template    => [ 'contents', 'endorsement' ],
      title       => loc( $req, $uri ? 'endorsement_edit_heading'
                                     : 'endorsement_create_heading' ), };
   my $args       =  $uri ? [ $name, $uri ] : [ $name ];
   my $fields     =  $page->{fields};

   if ($uri) {
      $fields->{type_code}->{disabled} = TRUE;
      $fields->{delete   } = delete_button $req, $uri, 'endorsement';
   }
   else {
      $fields->{endorsed } = bind 'endorsed', time2str '%Y-%m-%d';
   }

   $fields->{save} = save_button $req, $uri, 'endorsement';
   $fields->{href} = uri_for_action $req, 'blots/endorsement', $args;

   return $self->get_stash( $req, $page );
}

sub endorsements : Role(person_manager) {
   my ($self, $req) = @_;

   my $name    =  $req->uri_params->( 0 );
   my $page    =  {
      fields   => { headers  => $_endorsements_headers->( $req ),
                    rows     => [],
                    username => { name => $name }, },
      template => [ 'contents', 'table' ],
      title    => loc( $req, 'endorsements_management_heading' ), };
   my $blot_rs =  $self->schema->resultset( 'Endorsement' );
   my $actionp =  $self->moniker.'/endorsement';
   my $rows    =  $page->{fields}->{rows};

   $page->{fields}->{add} = $_add_endorsement_button->( $req, $actionp, $name );

   for my $blot (@{ $blot_rs->list_endorsements_for( $req, $name ) }) {
      push @{ $rows },
         [ { value => $blot->[ 0 ] },
           $self->$_endorsement_links( $req, $name, $blot->[ 1 ]->uri ) ];
   }

   return $self->get_stash( $req, $page );
}

sub create_endorsement_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name    = $req->uri_params->( 0 );
   my $blot_rs = $self->schema->resultset( 'Endorsement' );
   my $blot    = $blot_rs->new_result( { recipient => $name } );

   $self->$_update_endorsement_from_request( $req, $blot ); $blot->insert;

   my $action   = $self->moniker.'/endorsements';
   my $location = uri_for_action $req, $action, [ $name ];
   my $message  = [ 'Endorsement [_1] for [_2] added by [_3]',
                    $blot->type_code, $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub delete_endorsement_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name     = $req->uri_params->( 0 );
   my $uri      = $req->uri_params->( 1 );
   my $blot     = $self->$_find_endorsement_by( $name, $uri ); $blot->delete;
   my $action   = $self->moniker.'/endorsements';
   my $location = uri_for_action $req, $action, [ $name ];
   my $message  = [ 'Endorsement [_1] for [_2] deleted by [_3]',
                    $uri, $name, $req->username ];

   return { redirect => { location => $location, message => $message } };
}

sub update_endorsement_action : Role(person_manager) {
   my ($self, $req) = @_;

   my $name = $req->uri_params->( 0 );
   my $uri  = $req->uri_params->( 1 );
   my $blot = $self->$_find_endorsement_by( $name, $uri );

   $self->$_update_endorsement_from_request( $req, $blot ); $blot->update;

   my $message = [ 'Endorsement [_1] for [_2] updated by [_3]',
                   $uri, $name, $req->username ];

   return { redirect => { location => $req->uri, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Endorsement - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Endorsement;
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
