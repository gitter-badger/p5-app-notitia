package App::Notitia::Constants;

use strictures;
use parent 'Exporter::Tiny';

use App::Notitia::Exception;
use Class::Usul::Constants ();
use Data::Validation::Constants ();
use Web::ComposableRequest::Constants ();

Class::Usul::Constants->Exception_Class( 'App::Notitia::Exception' );
Data::Validation::Constants->Exception_Class( 'App::Notitia::Exception' );
Web::ComposableRequest::Constants->Exception_Class( 'App::Notitia::Exception' );

our @EXPORT = qw( DOTS HASH_CHAR SHIFT_TYPE_ENUM SLOT_TYPE_ENUM
                  TILDE TYPE_CLASS_ENUM VARCHAR_MAX_SIZE );

sub import {
   my $class       = shift;
   my $global_opts = { $_[ 0 ] && ref $_[ 0 ] eq 'HASH' ? %{+ shift } : () };
   my @wanted      = @_;
   my $class_usul  = {}; $class_usul->{ $_ } = 1 for (@wanted);
   my @self        = ();

   for (@EXPORT) { delete $class_usul->{ $_ } and push @self, $_ }

   $global_opts->{into} ||= caller;
   Class::Usul::Constants->import( $global_opts, keys %{ $class_usul } );
   $class->SUPER::import( $global_opts, @self );
   return;
}

sub DOTS      () { "\x{2026}" }
sub HASH_CHAR () { chr 35     }
sub TILDE     () { chr 126    }

sub VARCHAR_MAX_SIZE () { 255 }
sub SHIFT_TYPE_ENUM  () { [ qw( day night ) ] }
sub SLOT_TYPE_ENUM   () { [ qw( controller rider driver ) ] }
sub TYPE_CLASS_ENUM  () { [ qw( certification event role rota vehicle ) ] }

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Constants - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Constants;
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
