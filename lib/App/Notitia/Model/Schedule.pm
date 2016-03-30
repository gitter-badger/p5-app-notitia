package App::Notitia::Model::Schedule;

use App::Notitia::Attributes;   # Will do namespace cleaning
use App::Notitia::Constants qw( EXCEPTION_CLASS FALSE NUL SHIFT_TYPE_ENUM
                                SPC TRUE );
use App::Notitia::Util      qw( assign_link bind button dialog_anchor
                                js_anchor_config lcm_for loc
                                register_action_paths rota_navigation_links
                                set_element_focus slot_claimed slot_identifier
                                slot_limit_index table_link uri_for_action );
use Class::Usul::Functions  qw( sum throw );
use Class::Usul::Time       qw( time2str );
use HTTP::Status            qw( HTTP_EXPECTATION_FAILED );
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

   $stash->{nav }->{list    } = rota_navigation_links $req, 'month', $name;
   $stash->{page}->{location} = 'schedule';

   return $stash;
};

# Private class attributes
my $_rota_types_id = {};
my $_max_rota_cols = 4;

# Private functions
my $_add_js_dialog = sub {
   my ($req, $page, $args, $action, $name, $title) = @_;

   $name = "${action}-${name}"; $title = (ucfirst $action).SPC.$title;

   my $path = $page->{moniker}.'/slot';
   my $href = uri_for_action $req, $path, $args, { action => $action };
   my $js   = $page->{literal_js} //= [];

   push @{ $js }, dialog_anchor( $args->[ 2 ], $href, {
      name => $name, title => loc( $req, $title ), useIcon => \1 } );

   return;
};

my $_confirm_slot_button = sub {
   return button $_[ 0 ],
      { class =>  'right-last', label => 'confirm', value => $_[ 1 ].'_slot' };
};

my $_day_label = sub {
   my $map = { 0 => 1, 1 => 1, 2 => 2, 3 => 1 };
   my $v   = loc( $_[ 0 ], 'day_rota_heading_'.$_[ 1 ] );

   return { colspan => $map->{ $_[ 1 ] }, value => $v };
};

my $_day_rota_headers = sub {
   return [ map {  $_day_label->( $_[ 0 ], $_ ) } 0 .. $_max_rota_cols - 1 ];
};

my $_first_month_rota_date = sub {
   my $month = shift;
   my $date  = $month->set_time_zone( 'floating' )
                     ->truncate( to => 'day' )->set( day => 1 );

   while ($date->day_of_week > 1) { $date = $date->subtract( days => 1 ) }

   return $date;
};

my $_is_this_month = sub {
   my ($rno, $date) = @_; $rno > 0 and return TRUE;

   return $date->day < 15 ? TRUE : FALSE;
};

my $_month_label = sub {
   return { class => 'day-of-week',
            value => loc( $_[ 0 ], 'month_rota_heading_'.$_[ 1 ] ) };
};

my $_month_rota_headers = sub {
   return [ map {  $_month_label->( $_[ 0 ], $_ ) } 0 .. 6 ];
};

my $_month_rota_max_slots = sub {
   my $limits = shift;

   return [ sum( map { $limits->[ slot_limit_index $_, 'controller' ] }
                    @{ SHIFT_TYPE_ENUM() } ),
            sum( map { $limits->[ slot_limit_index 'day', $_ ] }
                       'rider', 'driver' ),
            sum( map { $limits->[ slot_limit_index 'night', $_ ] }
                       'rider', 'driver' ), ];
};

my $_month_rota_title = sub {
   my ($req, $rota_name, $month) = @_;

   my $title = ucfirst( loc( $req, $rota_name ) ).SPC
             . loc( $req, 'rota for' ).SPC.$month->month_name.SPC
             . $month->year;

   return $title;
};

my $_next_link = sub {
   my ($req, $actionp, $rota_name, $month) = @_;

   my $date = $month->set_time_zone( 'floating' )->truncate( to => 'day' )
                    ->set( day => 1 )->add( months => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_onchange_submit = sub {
   return js_anchor_config 'rota_date', 'submitForm', 'change',
                         [ 'rota_redirect', 'day-rota' ];
};

my $_onclick_relocate = sub {
   my ($k, $href) = @_;

   return js_anchor_config $k, 'location', 'click', [ "${href}" ];
};

my $_operators_vehicle = sub {
   my ($slot, $cache) = @_; $slot->operator->id or return NUL;

   exists $cache->{ $slot->operator->id }
      and return $cache->{ $slot->operator->id };

   my $pv      = ($slot->operator_vehicles->all)[ 0 ];
   my $pv_type = $pv ? $pv->type : NUL;
   my $label   = $pv_type eq '4x4' ? $pv_type
               : $pv_type eq 'car' ? ucfirst( $pv_type ) : undef;

   return $cache->{ $slot->operator->id } = $label;
};

my $_prev_link = sub {
   my ($req, $actionp, $rota_name, $month) = @_;

   my $date = $month->set_time_zone( 'floating' )->truncate( to => 'day' )
                    ->set( day => 1 )->subtract( months => 1 );

   return uri_for_action $req, $actionp, [ $rota_name, $date->ymd ];
};

my $_rota_summary_link = sub {
   my ($span, $opts) = @_;

   $opts or return { colspan => $span, value => '&nbsp;' x 2 };

   my $value = 'C'; my $class = 'vehicle-not-needed';

   if    ($opts->{vehicle    }) { $value = 'V'; $class = 'vehicle-assigned'  }
   elsif ($opts->{vehicle_req}) { $value = 'R'; $class = 'vehicle-requested' }

   return { class => $class, colspan => $span, value => $value };
};

my $_slot_label = sub {
   return slot_claimed( $_[ 1 ] ) ? $_[ 1 ]->{operator}->label
                                  : loc( $_[ 0 ], 'Vacant' );
};

my $_event_link = sub {
   my ($req, $page, $event) = @_;

   unless ($event) {
      my $name  = 'create-event';
      my $class = 'blank-event windows';
      my $href  = uri_for_action $req, 'event/event';

      push @{ $page->{literal_js} }, $_onclick_relocate->( $name, $href );

      return { class => $class, colspan => $_max_rota_cols, name => $name, };
   }

   my $name = my $value = $event->name;
   my $href = uri_for_action $req, 'event/event_summary', [ $event->uri ];
   my $tip  = loc $req, 'Click to view the [_1] event', [ $event->label ];

   return {
      colspan  => $_max_rota_cols - 2,
      value    => {
         class => 'table-link', hint => loc( $req, 'Hint' ),
         href  => $href,        name => $name,
         tip   => $tip,         type => 'link',
         value => $value, }, };
};

my $_participents_link = sub {
   my ($req, $page, $event) = @_; $event or return;

   my $class = 'list-icon';
   my $name  = 'view-participents';
   my $href  = uri_for_action $req, 'event/participents', [ $event->uri ];
   my $tip   = loc $req, 'participents_view_link', [ $event->label ];

   return { class   => 'narrow',
            colspan => 1,
            value   => { class => $class, hint => loc( $req, 'Hint' ),
                         href  => $href,  name => $name,
                         tip   => $tip,   type => 'link',
                         value => '&nbsp;', } };
};

my $_slot_link = sub {
   my ($req, $page, $rows, $k, $slot_type) = @_;

   my $claimed = slot_claimed $rows->{ $k };
   my $value   = $_slot_label->( $req, $rows->{ $k } );
   my $tip     = loc( $req, ($claimed ? 'yield_slot_tip' : 'claim_slot_tip'),
                      $slot_type );

   return { colspan => 2, value => table_link( $req, $k, $value, $tip ) };
};

my $_summary_cells = sub {
   my ($shift_types, $slot_types, $limits, $span, $rows) = @_; my $cells = [];

   for my $shift_type (@{ $shift_types }) {
      for my $slot_type (@{ $slot_types }) {
         my $i = slot_limit_index $shift_type, $slot_type;

         for my $slotno (0 .. $limits->[ $i ] - 1) {
            push @{ $cells }, $_rota_summary_link->
               ( $span, $rows->{ "${shift_type}_${slot_type}_${slotno}" } );
         }
      }
   }

   return $cells;
};

my $_vreq_state = sub {
   my ($tports, $vreqs) = @_;

   my $nvreqs = $vreqs->get_column( 'quantity' )->sum;

   return { vehicle     => ($tports == $nvreqs ? TRUE : FALSE),
            vehicle_req => TRUE };
};

my $_vehicle_request_link = sub {
   my ($schema, $req, $page, $event) = @_; $event or return;

   my $name     = 'view-vehicle-requests';
   my $href     = uri_for_action $req, 'asset/request_vehicle', [ $event->uri ];
   my $tip      = loc $req, 'vehicle_request_link', [ $event->label ];
   my $tport_rs = $schema->resultset( 'Transport' );
   my $tports   = $tport_rs->count( { event_id => $event->id } );
   my $vreq_rs  = $schema->resultset( 'VehicleRequest' );
   my $vreqs    = $vreq_rs->search( { event_id => $event->id } );
   my $opts     = $vreqs->count ? $_vreq_state->( $tports, $vreqs ) : FALSE;
   my $link     = $_rota_summary_link->( 1, $opts );

   $link->{class} .= ' small-slot';
   $link->{value}  = { hint  => loc( $req, 'Hint' ),
                       href  => $href,
                       name  => $name,
                       tip   => $tip,
                       type  => 'link',
                       value => $link->{value}, };

   return $link;
};

my $_controllers = sub {
   my ($req, $page, $rota_name, $rota_date, $rows, $limits) = @_;

   my $rota = $page->{rota}; my $controls = $rota->{controllers};

   for my $shift_type (@{ SHIFT_TYPE_ENUM() }) {
      my $max_slots = $limits->[ slot_limit_index $shift_type, 'controller' ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k      = "${shift_type}_controller_${subslot}";
         my $action = slot_claimed( $rows->{ $k } ) ? 'yield' : 'claim';
         my $args   = [ $rota_name, $rota_date, $k ];
         my $link   = $_slot_link->( $req, $page, $rows, $k, 'controller');

         push @{ $controls },
            [ { class => 'rota-header', value   => loc( $req, $k ), },
              { class => 'centre',      colspan => $_max_rota_cols,
                value => $link->{value} } ];

         $_add_js_dialog->( $req, $page, $args, $action,
                            'controller-slot', 'Controller Slot' );
      }
   }

   return;
};

my $_driver_row = sub {
   my ($req, $page, $args, $rows) = @_; my $k = $args->[ 2 ];

   return [ { value => loc( $req, $k ), class => 'rota-header' },
            { value => undef },
            $_slot_link->( $req, $page, $rows, $k, 'driver' ),
            { value => $rows->{ $k }->{ops_veh}, class => 'narrow' }, ];
};

my $_events = sub {
   my ($schema, $req, $page, $name, $rota_dt, $todays_events) = @_;

   my $date   = $rota_dt->day_abbr.SPC.$rota_dt->day;
   my $href   = uri_for_action $req, $page->{moniker}.'/day_rota';
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
   my $col1   = { value => $picker, class => 'rota-date narrow' };
   my $first  = TRUE;

   while (defined (my $event = $todays_events->next) or $first) {
      my $col2 = $_vehicle_request_link->( $schema, $req, $page, $event );
      my $col3 = $_event_link->( $req, $page, $event );
      my $col4 = $_participents_link->( $req, $page, $event );
      my $cols = [ $col1, $col2, $col3 ];

      $col4 and push @{ $cols }, $col4;
      push @{ $page->{rota}->{events} }, $cols;
      $col1 = { value => undef }; $first = FALSE;
   }

   push @{ $page->{literal_js} }, $_onchange_submit->();
   return;
};

my $_rider_row = sub {
   my ($req, $page, $args, $rows) = @_; my $k = $args->[ 2 ];

   return [ { value => loc( $req, $k ), class => 'rota-header' },
            assign_link( $req, $page, $args, $rows->{ $k } ),
            $_slot_link->( $req, $page, $rows, $k, 'rider' ),
            { value => $rows->{ $k }->{ops_veh}, class => 'narrow' }, ];
};

my $_riders_n_drivers = sub {
   my ($req, $page, $rota_name, $rota_date, $rows, $limits) = @_;

   my $shift_no = 0;

   for my $shift_type (@{ SHIFT_TYPE_ENUM() }) {
      my $shift     = $page->{rota}->{shifts}->[ $shift_no++ ] = {};
      my $riders    = $shift->{riders } = [];
      my $drivers   = $shift->{drivers} = [];
      my $max_slots = $limits->[ slot_limit_index $shift_type, 'rider' ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k      = "${shift_type}_rider_${subslot}";
         my $action = slot_claimed( $rows->{ $k } ) ? 'yield' : 'claim';
         my $args   = [ $rota_name, $rota_date, $k ];

         push @{ $riders }, $_rider_row->( $req, $page, $args, $rows );
         $_add_js_dialog->( $req, $page, $args, $action,
                            'rider-slot', 'Rider Slot' );
      }

      $max_slots = $limits->[ slot_limit_index $shift_type, 'driver' ];

      for (my $subslot = 0; $subslot < $max_slots; $subslot++) {
         my $k      = "${shift_type}_driver_${subslot}";
         my $action = slot_claimed( $rows->{ $k } ) ? 'yield' : 'claim';
         my $args   = [ $rota_name, $rota_date, $k ];

         push @{ $drivers }, $_driver_row->( $req, $page, $args, $rows );
         $_add_js_dialog->( $req, $page, $args, $action,
                            'driver-slot', 'Driver Slot' );
      }
   }

   return;
};

# Private methods
my $_find_rota_type_id_for = sub {
   return $_[ 0 ]->schema->resultset( 'Type' )->find_rota_by( $_[ 1 ] )->id;
};

my $_summary_table = sub {
   my ($self, $page, $date, $has_event, $rows) = @_;

   my $rota   = $page->{rota};
   my $lcm    = $rota->{lcm};
   my $limits = $self->config->slot_limits;
   my $span   = $lcm / $rota->{max_slots}->[ 0 ];
   my $table  = { class => 'month-rota', rows => [], type => 'table' };

   push @{ $table->{rows} },
      [ { colspan =>     $lcm / 4, value => $date->day },
        { colspan => 3 * $lcm / 4, value => $has_event } ];

   push @{ $table->{rows} }, $_summary_cells->
      ( [ 'day', 'night' ], [ 'controller' ], $limits, $span, $rows );

   $span = $lcm / $rota->{max_slots}->[ 1 ];

   push @{ $table->{rows} }, $_summary_cells->
      ( [ 'day' ], [ 'rider', 'driver' ], $limits, $span, $rows );

   $span = $lcm / $rota->{max_slots}->[ 2 ];

   push @{ $table->{rows} }, $_summary_cells->
      ( [ 'night' ], [ 'rider', 'driver' ], $limits, $span, $rows );

   return $table;
};

my $_rota_summary = sub {
   my ($self, $req, $page, $name, $date) = @_;

   my $type_id   = $self->$_find_rota_type_id_for( $name );
   my $slot_rs   = $self->schema->resultset( 'Slot' );
   # TODO: Do not need the personal_vehicle join
   my $slots     = $slot_rs->list_slots_for( $type_id, $date->ymd );
   my $event_rs  = $self->schema->resultset( 'Event' );
   my $events    = $event_rs->count_events_for( $type_id, $date->ymd );
   my $has_event = $events > 0 ? loc( $req, 'Events' ) : NUL;
   my $rows      = {};

   for my $slot ($slots->all) {
      my $shift = $slot->shift;
      my $key   = $shift->type_name.'_'.$slot->type_name.'_'.$slot->subslot;

      $rows->{ $key } = { name        => $key,
                          vehicle     => $slot->vehicle,
                          vehicle_req => $slot->bike_requested };
   }

   my $table   = $self->$_summary_table( $page, $date, $has_event, $rows );
   my $actionp = $self->moniker.'/day_rota';
   my $href    = uri_for_action $req, $actionp, [ $name, $date->ymd ];
   my $id      = "${name}_".$date->ymd;

   push @{ $page->{literal_js} }, $_onclick_relocate->( $id, $href );

   return { class => 'month-rota windows', name => $id, value => $table };
};

my $_get_page = sub {
   my ($self, $req, $name, $date, $todays_events, $rows) = @_;

   my $schema  =  $self->schema;
   my $rota_dt =  $self->local_dt( $date );
   my $limits  =  $self->config->slot_limits;
   my $title   =  ucfirst( loc( $req, $name ) ).SPC.loc( $req, 'rota for' ).SPC
               .  $rota_dt->month_name.SPC.$rota_dt->day.SPC.$rota_dt->year;
   my $actionp =  $self->moniker.'/day_rota';
   my $next    =  uri_for_action $req, $actionp,
                  [ $name, $rota_dt->clone->add( days => 1 )->ymd ];
   my $prev    =  uri_for_action $req, $actionp,
                  [ $name, $rota_dt->clone->subtract( days => 1 )->ymd ];
   my $page    =  {
      fields   => { nav => { next => $next, prev => $prev }, },
      moniker  => $self->moniker,
      rota     => { controllers => [],
                    events      => [],
                    headers     => $_day_rota_headers->( $req ),
                    shifts      => [], },
      template => [ 'contents', 'rota', 'rota-table' ],
      title    => $title };

   $_events->( $schema, $req, $page, $name, $rota_dt, $todays_events );
   $_controllers->( $req, $page, $name, $date, $rows, $limits );
   $_riders_n_drivers->( $req, $page, $name, $date, $rows, $limits );

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
   my $person    = $person_rs->find_by_shortcode( $req->username );

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $name, 3;

   # Without tz will create rota records prev. day @ 23:00 during summer time
   $person->claim_slot( $rota_name, $rota_date, $shift_type,
                        $slot_type, $subslot,   $bike );

   my $args     = [ $rota_name, $rota_date ];
   my $location = uri_for_action $req, 'sched/day_rota', $args;
   my $label    = slot_identifier
                     $rota_name, $rota_date, $shift_type, $slot_type, $subslot;
   my $message  = [ 'User [_1] claimed slot [_2]', $person->label, $label ];

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
   my $events   = $event_rs->find_events_for( $type_id, $date );
   my $rows     = {};

   for my $slot ($slots->all) {
      my $shift = $slot->shift;
      my $key   = $shift->type_name.'_'.$slot->type_name.'_'.$slot->subslot;

      $rows->{ $key }
         = { name        => $key,
             operator    => $slot->operator,
             ops_veh     => $_operators_vehicle->( $slot, $vehicle_cache ),
             vehicle     => $slot->vehicle,
             vehicle_req => $slot->bike_requested };
   }

   my $page = $self->$_get_page( $req, $name, $date, $events, $rows );

   return $self->get_stash( $req, $page );
}

sub month_rota : Role(any) {
   my ($self, $req) = @_;

   my $params    =  $req->uri_params;
   my $rota_name =  $params->( 0, { optional => TRUE } ) // 'main';
   my $rota_date =  $params->( 1, { optional => TRUE } ) // time2str '%Y-%m-01';
   my $rota_dt   =  $self->local_dt( $rota_date );
   my $title     =  $_month_rota_title->( $req, $rota_name, $rota_dt );
   my $max_slots =  $_month_rota_max_slots->( $self->config->slot_limits );
   my $lcm       =  lcm_for 4, @{ $max_slots };
   my $actionp   =  $self->moniker.'/month_rota';
   my $prev      =  $_prev_link->( $req, $actionp, $rota_name, $rota_dt->clone);
   my $next      =  $_next_link->( $req, $actionp, $rota_name, $rota_dt->clone);
   my $page      =  {
      fields     => { nav => { next => $next, prev => $prev }, },
      rota       => { headers => $_month_rota_headers->( $req ),
                      lcm => $lcm, max_slots => $max_slots, rows => [] },
      template   => [ 'contents', 'rota', 'month-table' ],
      title      => $title, };
   my $first     =  $_first_month_rota_date->( $rota_dt->clone );

   for my $rno (0 .. 5) {
      my $row = []; my $dayno;

      for my $cno (0 .. 6) {
         my $date  = $first->clone->add( days => 7 * $rno + $cno );
         my $cell  = { class => 'month-rota', value => NUL };

         $dayno = $date->day; $rno > 3 and $dayno == 1 and last;
         $_is_this_month->( $rno, $date )
            and $cell = $self->$_rota_summary( $req, $page, $rota_name, $date );
         push @{ $row }, $cell;
      }

      $row->[ 0 ] and push @{ $page->{rota}->{rows} }, $row;
      $rno > 3 and $dayno == 1 and last;
   }

   return $self->get_stash( $req, $page );
}

sub rota_redirect_action : Role(any) {
   my ($self, $req) = @_;

   my $period    = 'day';
   my $params    = $req->body_params;
   my $rota_name = $params->( 'rota_name' );
   my $rota_dt   = $self->local_dt( $params->( 'rota_date' ) );
   my $args      = [ $rota_name, $rota_dt->ymd ];
   my $location  = uri_for_action $req, $self->moniker."/${period}_rota", $args;
   my $message   = [ $req->session->collect_status_message( $req ) ];

   return { redirect => { location => $location, message => $message } };
}

sub slot : Role(rota_manager) Role(bike_rider) Role(controller) Role(driver) {
   my ($self, $req) = @_;

   my $params = $req->uri_params;
   my $name   = $params->( 2 );
   my $args   = [ $params->( 0 ), $params->( 1 ), $name ];
   my $action = $req->query_params->( 'action' );
   my $stash  = $self->dialog_stash( $req, "${action}-slot" );
   my $page   = $stash->{page};
   my $fields = $page->{fields};

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $name, 3;

   $fields->{confirm  } = $_confirm_slot_button->( $req, $action );
   $fields->{slot_href} = uri_for_action( $req, $self->moniker.'/slot', $args );

   $action eq 'claim' and $slot_type eq 'rider'
      and $fields->{request_bike}
         = bind( 'request_bike', TRUE, { container_class => 'right-last' } );

   return $stash;
}

sub yield_slot_action : Role(rota_manager) Role(bike_rider) Role(controller)
                        Role(driver) {
   my ($self, $req) = @_;

   my $params    = $req->uri_params;
   my $rota_name = $params->( 0 );
   my $rota_date = $params->( 1 );
   my $slot_name = $params->( 2 );
   my $person_rs = $self->schema->resultset( 'Person' );
   my $person    = $person_rs->find_by_shortcode( $req->username );

   my ($shift_type, $slot_type, $subslot) = split m{ _ }mx, $slot_name, 3;

   $person->yield_slot( $rota_name, $rota_date, $shift_type,
                        $slot_type, $subslot );

   my $args     = [ $rota_name, $rota_date ];
   my $location = uri_for_action( $req, 'sched/day_rota', $args );
   my $label    = slot_identifier( $rota_name, $rota_date,
                                   $shift_type, $slot_type, $subslot );
   my $message  = [ 'User [_1] yielded slot [_2]', $person->label, $label ];

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
