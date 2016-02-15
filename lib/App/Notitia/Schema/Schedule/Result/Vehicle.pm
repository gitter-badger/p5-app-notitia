package App::Notitia::Schema::Schedule::Result::Vehicle;

use strictures;
use overload '""' => sub { $_[ 0 ]->_as_string }, fallback => 1;
use parent   'App::Notitia::Schema::Base';

use App::Notitia::Constants qw( NUL );
use App::Notitia::Util      qw( foreign_key_data_type
                                nullable_foreign_key_data_type
                                nullable_varchar_data_type serial_data_type
                                varchar_data_type );

my $class = __PACKAGE__; my $result = 'App::Notitia::Schema::Schedule::Result';

$class->table( 'vehicle' );

$class->add_columns
   ( id       => serial_data_type,
     type     => foreign_key_data_type,
     owner    => nullable_foreign_key_data_type,
     aquired  => { data_type => 'datetime' },
     disposed => { data_type => 'datetime' },
     vrn      => varchar_data_type( 16, NUL ),
     name     => varchar_data_type( 64, NUL ),
     notes    => nullable_varchar_data_type, );

$class->set_primary_key( 'id' );

$class->belongs_to( owner => "${result}::Person", 'owner',
                    { join_type => 'left' } );
$class->belongs_to( type  => "${result}::Type" );

# Private methods
sub _as_string {
   return $_[ 0 ]->name ? $_[ 0 ]->name : $_[ 0 ]->type;
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
