package App::Notitia::Model::Schedule;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE HASH_CHAR NUL
                                SHIFT_TYPE_ENUM SPC TILDE TRUE );
use App::Notitia::Util      qw( bind loc register_action_paths
                                rota_navigation_links set_element_focus
                                slot_identifier slot_limit_index
                                uri_for_action );
use Class::Usul::Functions  qw( throw );
use Class::Usul::Time       qw( str2date_time time2str );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
use Scalar::Util            qw( blessed );
use Moo;

extends q(App::Notitia::Model);
with    q(App::Notitia::Role::PageConfiguration);
with    q(App::Notitia::Role::WebAuthorisation);
with    q(Class::Usul::TraitFor::ConnectInfo);
with    q(App::Notitia::Role::Schema);

# Public attributes
has '+moniker' => default => 'sched';

register_action_paths
   'sched/day_rota'   => 'day-rota',
   'sched/month_rota' => 'month-rota',
   'sched/slot'       => 'slot';

# Construction
around 'get_stash' => sub {
   my ($orig, $self, $req, @args) = @_;

   my $stash  = $orig->( $self, $req, @args );
   my $name   = $req->uri_params->( 0, { optional => TRUE } ) // 'main';

   $stash->{nav } = rota_navigation_links $req, 'month', $name;
   $stash->{page}->{location} = 'schedule';

   return $stash;
};

# Private class attributes
my $_rota_types_id = {};
my $_table_cols = 3;

# Private functions
my $_confirm_slot_button = sub {
   my ($req, $slot_type, $action) = @_;

   my $tip   = loc( $req, 'Hint' ).SPC.TILDE.SPC
             . loc( $req, "confirm_${action}_tip", [ $slot_type ] );
   my $value = "${action}_slot";

   # Have left tip off as too noisey
   return { class => 'right-last', label => 'confirm', value => $value };
};

my $_event_link = sub {
   my ($req, $event) = @_; $event or return NUL;

   my $name = my $value = $event->name;
   my $href = uri_for_action $req, 'event/summary', [ $event->uri ];
   my $tip  = loc $req, 'Click to view the [_1] event', [ $event->label ];

   return { class => 'table-link', hint  => loc( $req, 'Hint' ),
            href  => $href,        name  => $name,
            tip   => $tip,         type  => 'link',
            value => $value, };
};

my $_header_label = sub {
   return { value => loc( $_[ 0 ], 'rota_heading_'.$_[ 1 ] ) }
};

my $_headers = sub {
   return [ map {  $_header_label->( $_[ 0 ], $_ ) } 0 .. $_table_cols ];
};

my $_onchange_submit = sub {
   return "   behaviour.config.anchors[ 'rota_date' ] = {",
          "      method    : 'submitForm',",
          "      event     : 'change',",
          "      args      : [ 'rota_redirect', 'day-rota' ] };";
};

my $_onclick_relocate = sub {
   my ($k, $href) = @_;

   return "   behaviour.config.anchors[ '${k}' ] = {",
          "      method    : 'location',",
          "      event     : 'click',",
          "      args      : [ '${href}' ] };";
};

my $_operators_vehicle = sub {
   my ($slot, $cache) = @_; $slot->operator->id or return NUL;

   exists $cache->{ $slot->operator->id }
      and return $cache->{ $slot->operator->id };

   my $pv      = ($slot->personal_vehicles->all)[ 0 ];
   my $pv_type = $pv ? $pv->type : NUL;
   my $label   = $pv_type eq '4x4' ? $pv_type
               : $pv_type eq 'car' ? ucfirst( $pv_type ) : undef;

   return $cache->{ $slot->operator->id } = $label;
};

my $_rota_summary_link = sub {
   my ($span, $row) = @_;

   $row or return { colspan => $span, value => '&nbsp;' x 2 };

   my $value = 'C'; my $class = 'vehicle-not-needed';

   if    ($row->{vehicle }) { $value = 'V'; $class = 'vehicle-assigned'  }
   elsif ($row->{bike_req}) { $value = 'R'; $class = 'vehicle-requested' }

   return { class => $class, colspan => $span, value => $value };
};

my $_slot_claimed = sub {
   return exists $_[ 0 ]->{ $_[ 1 ] }
       && exists $_[ 0 ]->{ $_[ 1 ] }->{operator} ? TRUE : FALSE;
};

my $_slot_label = sub {
   return $_slot_claimed->( $_[ 1 ], $_[ 2 ] )
        ? $_[ 1 ]->{ $_[ 2 ] }->{operator}->label : loc( $_[ 0 ], 'Vacant' );
};

my $_table_link = sub {
   my ($req, $k, $value, $tip) = @_;

   return { class => 'table-link windows', hint  => loc( $req, 'Hint' ),
            href  => HASH_CHAR,            name  => $k,
            tip   => $tip,                 type  => 'link',
            value => $value, };
};

# Private methods
my $_add_js_dialog = sub {
   my ($self, $req, $page, $args, $action, $name, $title) = @_;

   $name = "${action}-${name}"; $title = (ucfirst $action).SPC.$title;

   my $path = $self->moniker.'/slot';
   my $href = uri_for_action( $req, $path, $args, { action => $action } );
   my $js   = $page->{literal_js} //= [];

   push @{ $js }, $self->dialog_anchor( $args->[ 2 ], $href, {
      name => $name, title => loc( $req, $title ), useIcon => \1 } );

   return;
};

my $_events = sub {
   my ($self, $req, $page, $name, $rota_dt, $todays_events) = @_;

   my $date   = $rota_dt->day_abbr.SPC.$rota_dt->day;
   my $href   = uri_for_action $req, $self->moniker.'/day_rota';
   my $picker = { class       => 'rota-date-form',
                  content     => {
                     list     => [ {
                        name  => 'rota_name',
                        type  => 'hidden',
                        value => $name, }, {
                        class => 'rota-date-field submit',
                        name  => 'rota_date',
                        label => NUL,
                        type  => 'date',
                        value => $date, } ],
                     type     => 'list', },
                  form_name   => 'day-rota',
                  href        => $href,
                  type        => 'form', };
   my $col1   = { value => $picker, class => 'rota-date' };
   my $first  = TRUE;

   while (defined (my $event = $todays_events->next) or $first) {
      my $col2 = { value   => $_event_link->( $req, $event ),
                   colspan => $_table_cols };

      push @{ $page->{rota}->{events} }, [ $col1, $col2 ];
      $col1 = { value => undef }; $first = FALSE;
   }

   push @{ $page->{literal_js} }, $_onchange_submit->();
   return;
};

my $_find_rota_type_id_for = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] )->id;
};

my $_rota_summary = sub {
   my ($self, $req, $page, $name, $date) = @_;

   my $type_id   = $self->$_find_rota_type_id_for( $name );
   my $slot_rs   = $self->schema->resultset( 'Slot' );
   # TODO: Do not need the personal_vehicle join
   my $slots     = $slot_rs->list_slots_for( $type_id, $date->ymd );
   my $event_rs  = $self->schema->resultset( 'Event' );
   my $events    = $event_rs->find_event_for( $type_id, $date->ymd );
   # TODO: Should be done with count_rs
   my $has_event = ($events->all)[ 0 ] ? loc( $req, 'Events' ) : NUL;
   my $cell      = { class => 'month-rota', rows => [], type => 'table' };
   my $rows      = {};

   for my $slot ($slots->all) {
      my $shift = $slot->shift;

      $rows->{ $shift->type_name.'_'.$slot->type_name.'_'.$slot->subslot }
         = { vehicle => $slot->vehicle, bike_req => $slot->bike_requested };
   }

   push @{ $cell->{rows} }, [ { colspan => 3, value => $date->day },
                              { colspan => 9, value => $has_event } ];
   push @{ $cell->{rows} },
      [ $_rota_summary_link->( 4, $rows->{ 'day_controller_0'   } ),
        $_rota_summary_link->( 4, $rows->{ 'day_controller_1'   } ),
        $_rota_summary_link->( 4, $rows->{ 'night_controller_0' } ), ];
   push @{ $cell->{rows} },
      [ $_rota_summary_link->( 3, $rows->{ 'day_rider_0'  } ),
        $_rota_summary_link->( 3, $rows->{ 'day_rider_1'  } ),
        $_rota_summary_link->( 3, $rows->{ 'day_rider_2'  } ),
        $_rota_summary_link->( 3, $rows->{ 'day_driver_0' } ), ];
   push @{ $cell->{rows} },
      [ $_rota_summary_link->( 3, $rows->{ 'night_rider_0'  } ),
        $_rota_summary_link->( 3, $rows->{ 'night_rider_1'  } ),
        $_rota_summary_link->( 3, $rows->{ 'night_rider_2'  } ),
        $_rota_summary_link->( 3, $rows->{ 'night_driver_0' } ), ];

   my $actionp = $self->moniker.'/day_rota';
   my $href    = uri_for_action $req, $actionp, [ $name, $date->ymd ];
   my $id      = "${name}_".$date->ymd;

   push @{ $page->{literal_js} }, $_onclick_relocate->( $id, $href );

   return { class => 'month-rota windows', name => $id, value => $cell };
};

my $_slot_link = sub {
   my ($self, $req, $page, $rows, $k, $slot_type) = @_;

   my $claimed = $_slot_claimed->( $rows, $k );
   my $value   = $_slot_label->( $req, $rows, $k );
   my $tip     = loc( $req, ($claimed ? 'yield_slot_tip' : 'claim_slot_tip'),
                      $slot_type );

   return { value => $_table_link->( $req, $k, $value, $tip ) };
};

my $_vehicle_link = sub {
   my ($self, $req, $page, $args, $value, $action) = @_; my $k = $args->[ 2 ];

   my $path = "asset/${action}"; my $params = { action => $action };

   $action eq 'unassign' and $params->{vehicle} = $value;

   my $href = uri_for_action $req, $path, $args, $params;
   my $tip  = loc $req, "${action}_management_tip";
   my $js   = $page->{literal_js} //= [];

   push @{ $js }, $self->dialog_anchor( "${action}_${k}", $href, {
      name    => "${action}-vehicle",
      title   => loc( $req, (ucfirst $action).' Vehicle' ),
      useIcon => \1 } );

   $value = (blessed $value) ? $value->slotref : $value;

   return $_table_link->( $req, "${action}_${k}", $value, $tip );
};

my $_assign_link = sub { # Traffic lights
   my ($self, $req, $page, $args, $rows) = @_; my $k = $args->[ 2 ];

   my $bike  = $rows->{ $k }->{bike_req};
   my $value = $rows->{ $k }->{vehicle};
   my $state = $_slot_claimed->( $rows, $k ) ? 'vehicle-not-needed' : NUL;

   $bike  and $state = 'vehicle-requested';
   $value and $state = 'vehicle-assigned';

   if ($state eq 'vehicle-assigned') {
      $value = $self->$_vehicle_link( $req, $page, $args, $value, 'unassign' );
   }
   elsif ($state eq 'vehicle-requested') {
      $value = $self->$_vehicle_link
         ( $req, $page, $args, 'requested', 'assign' );
   }

   my $class = "centre narrow ${state}";

   return { value => $value, class => $class };
};

my $_controllers = sub {
   my ($self, $req, $page, $rota_name, $rota_date, $rows, $limits) = @_;

   my $rota = $page->{rota}; my $controls = $rota->{controllers};

   for my $shift_type (@{ SHIFT_TYPE_ENUM() }) {
      my $max_slots = $limits->[ slot_limit_index $shift_type, 'controller' ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k      = "${shift_type}_controller_${subslot}";
         my $action = $_slot_claimed->( $rows, $k ) ? 'yield' : 'claim';
         my $args   = [ $rota_name, $rota_date, $k ];
         my $link   = $self->$_slot_link( $req, $page, $rows, $k, 'controller');

         push @{ $controls },
            [ { class => 'rota-header', value   => loc( $req, $k ), },
              { class => 'centre',      colspan => $_table_cols,
                value => $link->{value} } ];

         $self->$_add_js_dialog( $req, $page, $args, $action,
                                 'controller-slot', 'Controller Slot' );
      }
   }

   return;
};

my $_driver_row = sub {
   my ($self, $req, $page, $args, $rows) = @_; my $k = $args->[ 2 ];

   return [ { value => loc( $req, $k ), class => 'rota-header' },
            { value => undef },
            $self->$_slot_link( $req, $page, $rows, $k, 'driver' ),
            { value => $rows->{ $k }->{ops_veh}, class => 'narrow' }, ];
};

my $_rider_row = sub {
   my ($self, $req, $page, $args, $rows) = @_; my $k = $args->[ 2 ];

   return [ { value => loc( $req, $k ), class => 'rota-header' },
            $self->$_assign_link( $req, $page, $args, $rows ),
            $self->$_slot_link( $req, $page, $rows, $k, 'rider' ),
            { value => $rows->{ $k }->{ops_veh}, class => 'narrow' }, ];
};

my $_riders_n_drivers = sub {
   my ($self, $req, $page, $rota_name, $rota_date, $rows, $limits) = @_;

   my $shift_no = 0;

   for my $shift_type (@{ SHIFT_TYPE_ENUM() }) {
      my $shift     = $page->{rota}->{shifts}->[ $shift_no++ ] = {};
      my $riders    = $shift->{riders } = [];
      my $drivers   = $shift->{drivers} = [];
      my $max_slots = $limits->[ slot_limit_index $shift_type, 'rider' ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k      = "${shift_type}_rider_${subslot}";
         my $action = $_slot_claimed->( $rows, $k ) ? 'yield' : 'claim';
         my $args   = [ $rota_name, $rota_date, $k ];

         push @{ $riders }, $self->$_rider_row( $req, $page, $args, $rows );
         $self->$_add_js_dialog( $req, $page, $args, $action,
                                 'rider-slot', 'Rider Slot' );
      }

      $max_slots = $limits->[ slot_limit_index $shift_type, 'driver' ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k      = "${shift_type}_driver_${subslot}";
         my $action = $_slot_claimed->( $rows, $k ) ? 'yield' : 'claim';
         my $args   = [ $rota_name, $rota_date, $k ];

         push @{ $drivers }, $self->$_driver_row( $req, $page, $args, $rows );
         $self->$_add_js_dialog( $req, $page, $args, $action,
                                 'driver-slot', 'Driver Slot' );
      }
   }

   return;
};

my $_get_page = sub {
   my ($self, $req, $name, $date, $todays_events, $rows) = @_;

   my $limits  =  $self->config->slot_limits;
   my $rota_dt =  str2date_time $date, 'GMT';
   my $title   =  ucfirst( loc( $req, $name ) ).SPC.loc( $req, 'rota for' ).SPC
               .  $rota_dt->month_name.SPC.$rota_dt->day.SPC.$rota_dt->year;
   my $actionp =  $self->moniker.'/day_rota';
   my $next    =  uri_for_action $req, $actionp,
                  [ $name, $rota_dt->clone->add( days => 1 )->ymd ];
   my $prev    =  uri_for_action $req, $actionp,
                  [ $name, $rota_dt->clone->subtract( days => 1 )->ymd ];
   my $page    =  {
      fields   => { nav => { next => $next, prev => $prev }, },
      rota     => { controllers => [],
                    events      => [],
                    headers     => $_headers->( $req ),
                    shifts      => [], },
      template => [ 'contents', 'rota', 'rota-table' ],
      title    => $title };

   $self->$_events( $req, $page, $name, $rota_dt, $todays_events );
   $self->$_controllers( $req, $page, $name, $date, $rows, $limits );
   $self->$_riders_n_drivers( $req, $page, $name, $date, $rows, $limits );

   return $page;
};

# Public methods
sub claim_slot_action : Role(bike_rider) Role(controller) Role(driver) {
   my ($self, $req) = @_;

   my $params    = $req->uri_params;
   my $rota_name = $params->( 0 );
   my $rota_date = $params->( 1 );
   my $name      = $params->( 2 );
   my $opts      = { optional => TRUE };
   my $bike      = $req->body_params->( 'request_bike', $opts ) // FALSE;
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_person_by( $req->username );

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $name, 3;

   # Without tz will create rota records prev. day @ 23:00 during summer time
   $person->claim_slot( $rota_name, $rota_date, $shift_type,
                        $slot_type, $subslot,   $bike );

   my $args     = [ $rota_name, $rota_date ];
   my $location = uri_for_action( $req, 'sched/day_rota', $args );
   my $label    = slot_identifier( $rota_name, $rota_date,
                                   $shift_type, $slot_type, $subslot );
   my $message  = [ 'User [_1] claimed slot [_2]', $req->username, $label ];

   return { redirect => { location => $location, message => $message } };
}

sub day_rota : Role(any) {
   my ($self, $req) = @_; my $vehicle_cache = {};

   my $params   = $req->uri_params;
   my $today    = time2str '%Y-%m-%d';
   my $name     = $params->( 0, { optional => TRUE } ) // 'main';
   my $date     = $params->( 1, { optional => TRUE } ) // $today;
   my $type_id  = $self->$_find_rota_type_id_for( $name );
   my $slot_rs  = $self->schema->resultset( 'Slot' );
   my $slots    = $slot_rs->list_slots_for( $type_id, $date );
   my $event_rs = $self->schema->resultset( 'Event' );
   my $events   = $event_rs->find_event_for( $type_id, $date );
   my $rows     = {};

   for my $slot ($slots->all) {
      my $shift = $slot->shift;

      $rows->{ $shift->type_name.'_'.$slot->type_name.'_'.$slot->subslot }
         = { vehicle  => $slot->vehicle,
             operator => $slot->operator,
             bike_req => $slot->bike_requested,
             ops_veh  => $_operators_vehicle->( $slot, $vehicle_cache ) };
   }

   my $page = $self->$_get_page( $req, $name, $date, $events, $rows );

   return $self->get_stash( $req, $page );
}

sub month_rota : Role(any) {
   my ($self, $req) = @_;

   my $params    =  $req->uri_params;
   my $rota_name =  $params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date =  $params->( 1, { optional => TRUE } ) // time2str '%Y-%m-01';
   my $month     =  str2date_time $rota_date, 'GMT';
   my $title     =  ucfirst( loc( $req, $rota_name ) ).SPC
                 .  loc( $req, 'rota for' ).SPC.$month->month_name.SPC
                 .  $month->year;
   my $page      =  {
      fields     => {},
      rota       => { rows => [] },
      template   => [ 'contents', 'rota', 'month-table' ],
      title      => $title, };
   my $first     =  $month->set_time_zone( 'floating' )
                          ->truncate( to => 'day' )->set( day => 1 );

   for my $rno (0 .. 4) {
      my $row = [];

      for my $cno (0 .. 6) {
         my $date = $first->clone->add( days => 7 * $rno + $cno );

         $rno == 4 and $date->day == 1 and last;
         push @{ $row }, $self->$_rota_summary( $req, $page, $rota_name, $date);
      }

      $row->[ 0 ] and push @{ $page->{rota}->{rows} }, $row;
   }

   return $self->get_stash( $req, $page );
}

sub rota_redirect_action : Role(any) {
   my ($self, $req) = @_;

   my $period    = 'day';
   my $params    = $req->body_params;
   my $rota_name = $params->( 'rota_name' );
   my $rota_date = str2date_time $params->( 'rota_date' ), 'GMT';
   my $args      = [ $rota_name, $rota_date->ymd ];
   my $location  = uri_for_action $req, $self->moniker."/${period}_rota", $args;

   return { redirect => { location => $location } };
}

sub slot : Role(administrator) Role(bike_rider) Role(controller) Role(driver) {
   my ($self, $req) = @_;

   my $params = $req->uri_params;
   my $name   = $params->( 2 );
   my $args   = [ $params->( 0 ), $params->( 1 ), $name ];
   my $action = $req->query_params->( 'action' );
   my $stash  = $self->dialog_stash( $req, "${action}-slot" );
   my $page   = $stash->{page};
   my $fields = $page->{fields};

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $name, 3;

   $fields->{confirm  } = $_confirm_slot_button->( $req, $slot_type, $action );
   $fields->{slot_href} = uri_for_action( $req, $self->moniker.'/slot', $args );

   $action eq 'claim' and $slot_type eq 'rider'
      and $fields->{request_bike}
         = bind( 'request_bike', TRUE, { container_class => 'right-last' } );

   return $stash;
}

sub yield_slot_action : Role(administrator) Role(bike_rider) Role(controller)
                        Role(driver) {
   my ($self, $req) = @_;

   my $params    = $req->uri_params;
   my $rota_name = $params->( 0 );
   my $rota_date = $params->( 1 );
   my $slot_name = $params->( 2 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_person_by( $req->username );

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $slot_name, 3;

   $person->yield_slot( $rota_name, $rota_date, $shift_type,
                        $slot_type, $subslot );

   my $args     = [ $rota_name, $rota_date ];
   my $location = uri_for_action( $req, 'sched/day_rota', $args );
   my $label    = slot_identifier( $rota_name, $rota_date,
                                   $shift_type, $slot_type, $subslot );
   my $message  = [ 'User [_1] yielded slot [_2]', $req->username, $label ];

   return { redirect => { location => $location, message => $message } };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Model::Schedule - People and resource scheduling

=head1 Synopsis

   use App::Notitia::Model::Schedule;
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
