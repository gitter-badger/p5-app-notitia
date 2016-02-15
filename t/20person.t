use t::boilerplate;

use Test::More;
use English qw( -no_match_vars );

use App::Notitia::Schema;

my $connection =  App::Notitia::Schema->new
   ( config    => { appclass => 'App::Notitia', tempdir => 't' } );
my $schema     =  $connection->schedule;
my $person_rs  =  $schema->resultset( 'Person' );
my $person     =  $person_rs->search( { name => 'john' } )->first;

$person and $person->delete;
$person =   $person_rs->create( { name => 'john', password => '12345678' } );
$person =   $person_rs->search( { name => 'john' } )->first;

eval { $person->authenticate( '12345678' ) }; my $e = $EVAL_ERROR;

is $e->class, 'AccountInactive', 'Inactive account throws on authentication';

is $person->authenticate( '12345678', 1 ), undef, 'Authenticates for update';

$person->activate;

is $person->authenticate( '12345678' ), undef, 'Authenticates when activated';

eval { $person->authenticate( 'nonono' ) }; $e = $EVAL_ERROR;

is $e->class, 'IncorrectPassword', 'Authenticate throws on incorrect password';

eval { $person_rs->create( { name => 'x', password => '12345678' } ) };

$e = $EVAL_ERROR; is $e->class, 'ValidationErrors', 'Validation errors';

is $e->args->[ 0 ]->class, 'ValidLength', 'Invalid name length';

my $type_rs    =  $schema->resultset( 'Type' );
my $rider_type =  $type_rs->search
   ( { name    => 'bike_rider', type => 'role' } )->single;
my $role_rs    =  $schema->resultset( 'Role' );
my $role       =  $role_rs->search
   ( { member  => $person->id, type => $rider_type->id } );

$role and $role->delete;
$role = $role_rs->create( { member => $person->id, type => $rider_type->id } );

done_testing;

# Local Variables:
# mode: perl
# tab-width: 3
# End:
# vim: expandtab shiftwidth=3:
