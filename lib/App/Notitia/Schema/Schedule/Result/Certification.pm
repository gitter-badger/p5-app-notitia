package App::Notitia::Schema::Schedule::Result::Certification;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia::Util qw( date_data_type foreign_key_data_type
                           varchar_data_type );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'certification' );

$class->add_columns
   ( recipient_id => foreign_key_data_type,
     type_id      => foreign_key_data_type,
     completed    => date_data_type,
     notes        => varchar_data_type, );

$class->set_primary_key( 'recipient_id', 'type_id' );

$class->belongs_to( recipient => "${result}::Person", 'recipient_id' );
$class->belongs_to( type      => "${result}::Type",   'type_id'      );

# Private methods
sub _as_string {
   return $_[ 0 ]->type;
}

sub delete {
   my $self = shift;

   $self->type eq 'catagory_b'
      and $self->recipient->is_member_of( 'bike_rider' )
      and $self->recipient->delete_member_from( 'bike_rider' );

   return $self->next::method;
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Schema::Schedule::Result::Certification - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Schema::Schedule::Result::Certification;
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