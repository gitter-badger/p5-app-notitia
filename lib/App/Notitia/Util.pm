package App::Notitia::Util;

use strictures;
use parent 'Exporter::Tiny';

use App::Notitia::Constants    qw( FALSE HASH_CHAR NUL SPC TILDE TRUE
                                   VARCHAR_MAX_SIZE );
use Class::Usul::Crypt::Util   qw( decrypt_from_config encrypt_for_config );
use Class::Usul::File;
use Class::Usul::Functions     qw( class2appdir create_token
                                   ensure_class_loaded find_apphome
                                   first_char fold get_cfgfiles io is_arrayref
                                   is_hashref is_member throw );
use Class::Usul::Time          qw( str2date_time str2time time2str );
use Crypt::Eksblowfish::Bcrypt qw( en_base64 );
use Data::Validation;
use HTTP::Status               qw( HTTP_OK );
use JSON::MaybeXS;
use Scalar::Util               qw( blessed weaken );
use Try::Tiny;
use YAML::Tiny;

our @EXPORT_OK = qw( assert_unique assign_link authenticated_only bind
                     bind_fields bool_data_type build_navigation build_tree
                     button check_field_js check_form_field clone
                     create_link date_data_type delete_button dialog_anchor
                     encrypted_attr enhance enumerated_data_type field_options
                     foreign_key_data_type get_hashed_pw get_salt is_draft
                     is_encrypted iterator js_anchor_config lcm_for
                     load_file_data loc localise_tree mail_domain make_id_from
                     make_name_from make_tip management_link mtime new_salt
                     nullable_foreign_key_data_type nullable_varchar_data_type
                     numerical_id_data_type register_action_paths save_button
                     serial_data_type set_element_focus
                     set_on_create_datetime_data_type slot_claimed
                     slot_identifier slot_limit_index show_node stash_functions
                     table_link to_dt uri_for_action varchar_data_type );

# Private class attributes
my $action_path_uri_map = {}; # Key is an action path, value a partial URI
my $field_option_cache  = {};
my $json_coder          = JSON::MaybeXS->new( utf8 => FALSE );
my $result_class_cache  = {};
my $translations        = {};
my $yaml_coder          = YAML::Tiny->new;

# Private functions
my $bind_option = sub {
   my ($v, $opts) = @_;

   my $prefix = $opts->{prefix} // NUL;
   my $numify = $opts->{numify} // FALSE;

   return is_arrayref $v
        ? { label =>  $v->[ 0 ].NUL,
            value => (defined $v->[ 1 ] ? ($numify ? 0 + ($v->[ 1 ] || 0)
                                                   : $prefix.$v->[ 1 ])
                                        : undef),
            %{ $v->[ 2 ] // {} } }
        : { label => "${v}", value => ($numify ? 0 + $v : $prefix.$v) };
};

my $_can_see_link = sub {
   my ($req, $node) = @_;

   ($node->{type} eq 'folder' or $req->authenticated) and return TRUE;

   my $roles = is_arrayref( $node->{role} ) ?   $node->{role}
             :              $node->{role}   ? [ $node->{role} ]
                                            : [];

   return is_member( 'anon', $roles ) ? TRUE : FALSE;
};

my $_check_field = sub {
   my ($schema, $req) = @_;

   my $params = $req->query_params;
   my $domain = $params->( 'domain' );
   my $class  = $params->( 'form'   );
   my $id     = $params->( 'id'     );
   my $val    = $params->( 'val', { raw => TRUE } );

   if (first_char $class eq '+') { $class = substr $class, 1 }
   else { $class = (blessed $schema)."::Result::${class}" }

   $result_class_cache->{ $class }
      or (ensure_class_loaded( $class )
          and $result_class_cache->{ $class } = TRUE);

   my $attr = $class->validation_attributes; $attr->{level} = 4;

   my $rs; $attr->{fields}->{ $id }->{unique} and $domain eq 'insert'
      and defined $val
      and $rs = $schema->resultset( $class )
      and assert_unique( $rs, { $id => $val }, $attr->{fields}, $id );

   return Data::Validation->new( $attr )->check_field( $id, $val );
};

my $extension2format = sub {
   my ($map, $path) = @_; my $extn = (split m{ \. }mx, $path)[ -1 ] // NUL;

   return $map->{ $extn } // 'text';
};

my $get_tip_text = sub {
   my ($root, $node) = @_;

   my $path = $node->{path} or return NUL; my $text = $path->abs2rel( $root );

   $text =~ s{ \A [a-z]+ / }{}mx; $text =~ s{ \. .+ \z }{}mx;
   $text =~ s{ [/] }{ / }gmx;     $text =~ s{ [_] }{ }gmx;

   return $text;
};

my $load_file_data = sub {
   load_file_data( $_[ 0 ] ); return TRUE;
};

my $sorted_keys = sub {
   my $node = shift;

   return [ sort { $node->{ $a }->{_order} <=> $node->{ $b }->{_order} }
            grep { first_char $_ ne '_' } keys %{ $node } ];
};

my $make_tuple = sub {
   my $node = shift;

   ($node and exists $node->{type} and defined $node->{type})
      or return [ 0, [], $node ];

   my $keys = $node->{type} eq 'folder' ? $sorted_keys->( $node->{tree} ) : [];

   return [ 0, $keys, $node ];
};

my $_vehicle_link = sub {
   my ($req, $page, $args, $opts) = @_;

   my $action = $opts->{action}; my $value = $opts->{value};

   my $path   = "asset/${action}"; my $params = { action => $action };

   $action eq 'unassign' and $params->{vehicle} = $value;
   $opts->{type} and $params->{type} = $opts->{type};

   my $href = uri_for_action( $req, $path, $args, $params );
   my $tip  = loc( $req, "${action}_management_tip" );
   my $js   = $page->{literal_js} //= [];
   my $name = $opts->{name};

   push @{ $js }, dialog_anchor( "${action}_${name}", $href, {
      name    => "${action}-vehicle",
      title   => loc( $req, (ucfirst $action).' Vehicle' ),
      useIcon => \1 } );

   $value = (blessed $value) ? $value->slotref : $value;

   return table_link( $req, "${action}_${name}", $value, $tip );
};

# Public functions
sub assert_unique ($$$$) {
   my ($rs, $columns, $fields, $k) = @_;

   defined $columns->{ $k } or return;
   is_arrayref $fields->{ $k }->{unique} and return;

   my $v = ($rs->search( { $k => $columns->{ $k } } )->all)[ 0 ];

   defined $v and throw 'Parameter [_1] is not unique', [ $k ];

   return;
}

sub assign_link ($$$$) {
   my ($req, $page, $args, $opts) = @_; my $type = $opts->{type};

   my $name = $opts->{name}; my $value = $opts->{vehicle};

   my $state = slot_claimed( $opts ) ? 'vehicle-not-needed' : NUL;

   $opts->{vehicle_req} and $state = 'vehicle-requested';
   $value and $state = 'vehicle-assigned';

   if ($state eq 'vehicle-assigned') {
      my $opts = { action => 'unassign', name => $name, value => $value };

      $value = $_vehicle_link->( $req, $page, $args, $opts );
   }
   elsif ($state eq 'vehicle-requested') {
      my $opts = { action => 'assign', name => $name, value => 'requested' };

      $type and $opts->{type} = $type;
      $value = $_vehicle_link->( $req, $page, $args, $opts );
   }

   my $class = "centre narrow ${state}";

   return { value => $value, class => $class };
}

sub authenticated_only ($) {
   my $assets = shift;

   return sub {
      $_ =~ m{ \A / $assets         }mx or  return FALSE;
      $_ =~ m{ \A / $assets /public }mx and return TRUE;

      return $_[ 1 ]->{ 'psgix.session' }->{authenticated} ? TRUE : FALSE;
   };
}

sub bind ($;$$) {
   my ($name, $v, $opts) = @_; $opts = { %{ $opts // {} } };

   my $numify = $opts->{numify} // FALSE;
   my $params = { label => $name, name => $name }; my $class;

   if (defined $v and $class = blessed $v and $class eq 'DateTime') {
      $params->{value} = $v->dmy( '/' );
   }
   elsif (is_arrayref $v) {
      $params->{value} = [ map { $bind_option->( $_, $opts ) } @{ $v } ];
   }
   else { defined $v and $params->{value} = $numify ? 0 + $v : "${v}" }

   delete $opts->{numify}; delete $opts->{prefix};

   $params->{ $_ } = $opts->{ $_ } for (keys %{ $opts });

   return $params;
}

sub bind_fields ($$$$) {
   my ($schema, $src, $map, $result) = @_; my $fields = {};

   for my $k (keys %{ $map }) {
      my $value = exists $map->{ $k }->{checked} ? TRUE : $src->$k();
      my $opts  = field_options( $schema, $result, $k, $map->{ $k } );

      $fields->{ $k } = &bind( $k, $value, $opts );
   }

   return $fields;
}

sub bool_data_type (;$) {
   return { data_type     => 'boolean',
            default_value => $_[ 0 ] // FALSE,
            is_nullable   => FALSE, };
}

sub build_navigation ($$) {
   my ($req, $opts) = @_; my @nav = ();

   my $ids = $req->uri_params->() // []; my $iter = iterator( $opts->{node} );

   while (defined (my $node = $iter->())) {
      $node->{id} eq 'index' and next; $_can_see_link->( $req, $node ) or next;

      if ($node->{type} eq 'folder') {
         my $keepit = FALSE; $node->{fcount} < 1 and next;

         for my $n (grep { not m{ \A _ }mx } keys %{ $node->{tree} }) {
            $_can_see_link->( $req, $node->{tree}->{ $n } ) and $keepit = TRUE
               and last;
         }

         $keepit or next;
      }

      my $link   = clone( $node ); delete $link->{tree};
      my $prefix = $link->{prefix};

      $link->{class}  = $node->{type} eq 'folder' ? 'folder-link' : 'file-link';
      $link->{tip  }  = $get_tip_text->( $opts->{config}->docs_root, $node );
      $link->{label}  = $opts->{label}->( $link );
      $link->{uri  }  = uri_for_action( $req, $opts->{path}, [ $link->{url} ] );
      $link->{depth} -= 2;

      if (defined $ids->[ 0 ] and $ids->[ 0 ] eq $node->{id}) {
         $link->{class} .= ' open'; shift @{ $ids };
      }

      push @nav, $link;
   }

   return \@nav;
}

sub build_tree {
   my ($map, $dir, $depth, $node_order, $url_base, $parent) = @_;

   $depth //= 0; $node_order //= 0; $url_base //= NUL; $parent //= NUL;

   my $fcount = 0; my $max_mtime = 0; my $tree = {}; $depth++;

   for my $path (grep { defined $_->stat } $dir->all) {
      my ($id, $pref) =  @{ make_id_from( $path->utf8->filename ) };
      my  $name       =  make_name_from( $id );
      my  $url        =  $url_base ? "${url_base}/${id}" : $id;
      my  $mtime      =  $path->stat->{mtime} // 0;
      my  $node       =  $tree->{ $id } = {
          depth       => $depth,
          format      => $extension2format->( $map, "${path}" ),
          id          => $id,
          modified    => $mtime,
          name        => $name,
          parent      => $parent,
          path        => $path,
          prefix      => $pref,
          title       => ucfirst $name,
          type        => 'file',
          url         => $url,
          _order      => $node_order++, };

      $path->is_file and ++$fcount and $load_file_data->( $node )
                     and $mtime > $max_mtime and $max_mtime = $mtime;
      $path->is_dir  or  next;
      $node->{type} = 'folder';
      $node->{tree} = $depth > 1 # Skip the language code directories
         ?  build_tree( $map, $path, $depth, $node_order, $url, $name )
         :  build_tree( $map, $path, $depth, $node_order );
      $fcount += $node->{fcount} = $node->{tree}->{_fcount};
      mtime( $node ) > $max_mtime and $max_mtime = mtime( $node );
   }

   $tree->{_fcount} = $fcount; $tree->{_mtime} = $max_mtime;

   return $tree;
}

sub button ($$;$$$) {
   my ($req, $opts, $action, $name, $args) = @_; my $class = $opts->{class};

   my $conk   = $action && $name ? 'container_class' : 'class';
   my $label  = $opts->{label} // "${action}_${name}";
   my $value  = $opts->{value} // "${action}_${name}";
   my $button = { $conk => $class, label => $label, value => $value };

   $action and $name
      and $button->{tip} = make_tip( $req, "${action}_${name}_tip", $args );

   return $button;
}

sub check_field_js ($$) {
   my ($k, $opts) = @_;

   my $args = $json_coder->encode( [ $k, $opts->{form}, $opts->{domain} ] );

   return "   behaviour.config.server[ '${k}' ] = {",
          "      method    : 'checkField',",
          "      event     : 'blur',",
          "      args      : ${args} };";
}

sub check_form_field ($$;$) {
   my ($schema, $req, $log) = @_; my $mesg;

   my $id = $req->query_params->( 'id' ); my $meta = { id => "${id}_ajax" };

   try   { $_check_field->( $schema, $req ) }
   catch {
      my $e = $_;

      $log and $log->debug( "${e}" );
      $mesg = $req->loc( $e->error, { params => $e->args } );
      $meta->{class_name} = 'field-error';
   };

   return { code => HTTP_OK,
            page => { content => { html => $mesg }, meta => $meta },
            view => 'json' };
}

sub clone (;$) {
   my $v = shift;

   is_arrayref $v and return [ @{ $v // [] } ];
   is_hashref  $v and return { %{ $v // {} } };
   return $v;
}

sub create_link ($$$;$) {
   my ($req, $actionp, $k, $opts) = @_; $opts //= {};

   return { class => $opts->{class} // NUL,
            container_class => $opts->{container_class} // NUL,
            hint  => loc( $req, 'Hint' ),
            href  => uri_for_action( $req, $actionp, $opts->{args} // [] ),
            name  => "create_${k}",
            tip   => loc( $req, "${k}_create_tip", [ $k ] ),
            type  => 'link',
            value => loc( $req, "${k}_create_link" ) };
}

sub date_data_type () {
   return { data_type     => 'datetime',
            default_value => '0000-00-00',
            is_nullable   => TRUE,
            datetime_undef_if_invalid => TRUE, }
}

sub delete_button ($$;$) {
   my ($req, $name, $opts) = @_; $opts //= {};

   my $class = $opts->{container_class} // 'delete-button right';
   my $tip   = make_tip( $req, 'delete_tip', [ $opts->{type}, $name ] );

   return { container_class => $class,
            label           => 'delete',
            tip             => $tip,
            value           => 'delete_'.$opts->{type}, };
}

sub dialog_anchor ($$$) {
   my ($k, $href, $opts) = @_;

   return js_anchor_config( $k, 'modalDialog', 'click', [ "${href}", $opts ] );
}

sub encrypted_attr ($$$$) {
   my ($conf, $file, $k, $default) = @_; my $data = {}; my $v;

   if ($file->exists) {
      $data = Class::Usul::File->data_load( paths => [ $file ] ) // {};
      $v    = decrypt_from_config $conf, $data->{ $k };
   }

   unless ($v) {
      $data->{ $k } = encrypt_for_config $conf, $v = $default->();
      Class::Usul::File->data_dump( { path => $file->assert, data => $data } );
   }

   return $v;
}

sub enhance ($) {
   my $conf = shift;
   my $attr = { config => { %{ $conf } }, }; $conf = $attr->{config};

   $conf->{appclass    } //= 'App::Notitia';
   $attr->{config_class} //= $conf->{appclass}.'::Config';
   $conf->{name        } //= class2appdir $conf->{appclass};
   $conf->{home        } //= find_apphome $conf->{appclass}, $conf->{home};
   $conf->{cfgfiles    } //= get_cfgfiles $conf->{appclass}, $conf->{home};

   return $attr;
}

sub enumerated_data_type ($;$) {
   return { data_type     => 'enum',
            default_value => $_[ 1 ],
            extra         => { list => $_[ 0 ] },
            is_enum       => TRUE, };
}

sub field_options ($$$;$) {
   my ($schema, $result, $name, $opts) = @_; my $mandy; $opts //= {};

   unless (defined ($mandy = $field_option_cache->{ $result }->{ $name })) {
      my $class       = blessed $schema->resultset( $result )->new_result( {} );
      my $constraints = $class->validation_attributes->{fields}->{ $name };

      $mandy = $field_option_cache->{ $result }->{ $name }
             = exists $constraints->{validate}
                   && $constraints->{validate} =~ m{ isMandatory }mx
             ? ' required' : NUL;
   }

   $opts->{class} //= NUL; $opts->{class} .= $mandy;

   return $opts;
}

sub foreign_key_data_type (;$$) {
   my $type_info = { data_type     => 'integer',
                     default_value => $_[ 0 ],
                     extra         => { unsigned => TRUE },
                     is_nullable   => FALSE,
                     is_numeric    => TRUE, };

   defined $_[ 1 ] and $type_info->{accessor} = $_[ 1 ];

   return $type_info;
}

sub gcf ($$) {
   my ($x, $y) = @_; ($x, $y) = ($y, $x % $y) while ($y); return $x;
}

sub get_hashed_pw ($) {
   my @parts = split m{ [\$] }mx, $_[ 0 ]; return substr $parts[ -1 ], 22;
}

sub get_salt ($) {
   my @parts = split m{ [\$] }mx, $_[ 0 ];

   $parts[ -1 ] = substr $parts[ -1 ], 0, 22;

   return join '$', @parts;
}

sub is_draft ($$) {
   my ($conf, $url) = @_; my $drafts = $conf->drafts; my $posts = $conf->posts;

   $url =~ m{ \A $drafts \b }mx and return TRUE;
   $url =~ m{ \A $posts / $drafts \b }mx and return TRUE;

   return FALSE;
}

sub is_encrypted ($) {
   return $_[ 0 ] =~ m{ \A \$\d+[a]?\$ }mx ? TRUE : FALSE;
}

sub iterator ($) {
   my $tree = shift; my @folders = ( $make_tuple->( $tree ) );

   return sub {
      while (my $tuple = $folders[ 0 ]) {
         while (defined (my $k = $tuple->[ 1 ]->[ $tuple->[ 0 ]++ ])) {
            my $node = $tuple->[ 2 ]->{tree}->{ $k };

            $node->{type} eq 'folder'
               and unshift @folders, $make_tuple->( $node );

            return $node;
         }

         shift @folders;
      }

      return;
   };
}

sub js_anchor_config ($$$$) {
   my ($k, $method, $event, $args) = @_; $args = $json_coder->encode( $args );

   return "   behaviour.config.anchors[ '${k}' ] = {",
          "      event     : '${event}',",
          "      method    : '${method}',",
          "      args      : ${args} };";
}

sub lcm ($$) {
   return $_[ 0 ] * $_[ 1 ] / gcf( $_[ 0 ], $_[ 1 ] );
}

sub lcm_for (@) {
   return ((fold { lcm $_[ 0 ], $_[ 1 ] })->( shift ))->( @_ );
}

sub load_file_data {
   my $node = shift; my $body = $node->{path}->all;

   my $yaml; $body =~ s{ \A --- $ ( .* ) ^ --- $ }{}msx and $yaml = $1;

   $yaml or return $body; my $data = $yaml_coder->read_string( $yaml )->[ 0 ];

   exists $data->{created} and $data->{created} = str2time $data->{created};

   $node->{ $_ } = $data->{ $_ } for (keys %{ $data });

   return $body;
}

sub loc ($$;@) {
   my ($req, $k, @args) = @_;

   $translations->{ my $locale = $req->locale } //= {};

   return exists $translations->{ $locale }->{ $k }
               ? $translations->{ $locale }->{ $k }
               : $translations->{ $locale }->{ $k } = $req->loc( $k, @args );
}

sub localise_tree ($$) {
   my ($tree, $locale) = @_; ($tree and $locale) or return FALSE;

   exists $tree->{ $locale } and defined $tree->{ $locale }
      and return $tree->{ $locale };

   return FALSE;
}

sub mail_domain {
   my $mailname_path = io[ NUL, 'etc', 'mailname' ]; my $domain = 'example.com';

   $mailname_path->exists and $domain = $mailname_path->chomp->getline;

   return $domain;
}

sub make_id_from ($) {
   my $v = shift; my ($p) = $v =~ m{ \A ((?: \d+ [_\-] )+) }mx;

   $v =~ s{ \A (\d+ [_\-])+ }{}mx; $v =~ s{ [_] }{-}gmx;

   $v =~ s{ \. [a-zA-Z0-9\-\+]+ \z }{}mx;

   defined $p and $p =~ s{ [_\-]+ \z }{}mx;

   return [ $v, $p // NUL ];
}

sub make_name_from ($) {
   my $v = shift; $v =~ s{ [_\-] }{ }gmx; return $v;
}

sub make_tip ($$;$) {
   my ($req, $k, $args) = @_; $args //= [];

   return loc( $req, 'Hint' ).SPC.TILDE.SPC.loc( $req, $k, $args );
}

sub management_link ($$$;$) {
   my ($req, $actionp, $name, $opts) = @_; $opts //= {};

   my $args   = $opts->{args} // [ $name ];
   my $params = $opts->{params} // {};
   my ($moniker, $action) = split m{ / }mx, $actionp, 2;
   my $href   = uri_for_action( $req, $actionp, $args, $params );
   my $type   = $opts->{type} // 'link';
   my $button = { class => 'table-link',
                  hint  => loc( $req, 'Hint' ),
                  href  => $href,
                  name  => "${name}-${action}",
                  tip   => loc( $req, "${action}_management_tip", @{ $args } ),
                  type  => $type,
                  value => loc( $req, "${action}_management_link" ), };

   if ($type eq 'form_button') {
      $button->{action   } = "${name}_${action}";
      $button->{form_name} = "${name}-${action}";
      $button->{tip      } = loc( $req, "${name}_${action}_tip", @{ $args } );
      $button->{value    } = loc( $req, "${name}_${action}_link" );
   }

   return $button;
}

sub mtime ($) {
   return $_[ 0 ]->{tree}->{_mtime};
}

sub new_salt ($$) {
   my ($type, $lf) = @_;

   return "\$${type}\$${lf}\$"
        . (en_base64( pack( 'H*', substr( create_token, 0, 32 ) ) ) );
}

sub nullable_foreign_key_data_type () {
   return { data_type         => 'integer',
            default_value     => undef,
            extra             => { unsigned => TRUE },
            is_nullable       => TRUE,
            is_numeric        => TRUE, };
}

sub nullable_varchar_data_type (;$$) {
   return { data_type         => 'varchar',
            default_value     => $_[ 1 ],
            is_nullable       => TRUE,
            size              => $_[ 0 ] || VARCHAR_MAX_SIZE, };
}

sub numerical_id_data_type (;$) {
   return { data_type         => 'smallint',
            default_value     => $_[ 0 ],
            is_nullable       => FALSE,
            is_numeric        => TRUE, };
}

sub register_action_paths (;@) {
   my $args = (is_hashref $_[ 0 ]) ? $_[ 0 ] : { @_ };

   for my $k (keys %{ $args }) { $action_path_uri_map->{ $k } = $args->{ $k } }

   return;
}

sub save_button ($$;$) {
   my ($req, $name, $opts) = @_; $opts //= {};

   my $action = $name ? 'update' : 'create';
   my $class  = $opts->{container_class} // 'save-button right-last';
   my $tip    = make_tip( $req, "${action}_tip", [ $opts->{type}, $name ] );

   return { container_class => $class,
            label           => $action,
            tip             => $tip,
            value           => "${action}_".$opts->{type} };
}

sub serial_data_type () {
   return { data_type         => 'integer',
            default_value     => undef,
            extra             => { unsigned => TRUE },
            is_auto_increment => TRUE,
            is_nullable       => FALSE,
            is_numeric        => TRUE, };
}

sub set_element_focus ($$) {
   my ($form, $name) = @_;

   return [ "var form = document.forms[ '${form}' ];",
            "var f = function() { behaviour.rebuild(); form.${name}.focus() };",
            'f.delay( 100 );', ];
}

sub set_on_create_datetime_data_type () {
   return { %{ date_data_type() }, set_on_create => TRUE };
}

sub show_node ($;$$) {
   my ($node, $wanted, $wanted_depth) = @_;

   $wanted //= NUL; $wanted_depth //= 0;

   return $node->{depth} >= $wanted_depth
       && $node->{url  } =~ m{ \A $wanted }mx ? TRUE : FALSE;
}

sub slot_claimed ($) {
   return defined $_[ 0 ] && exists $_[ 0 ]->{operator} ? TRUE : FALSE;
}

sub slot_identifier ($$$$$) {
   my ($rota_name, $rota_date, $shift_type, $slot_type, $subslot) = @_;

   $rota_name =~ s{ _ }{ }gmx;

   return sprintf '%s rota on %s %s shift %s slot %s',
          ucfirst( $rota_name ), $rota_date, $shift_type, $slot_type, $subslot;
}

sub slot_limit_index ($$) {
   my ($shift_type, $slot_type) = @_;

   my $shift_map = { day => 0, night => 1 };
   my $slot_map  = { controller => 0, driver => 4, rider => 2 };

   return $shift_map->{ $shift_type } + $slot_map->{ $slot_type };
}

sub stash_functions ($$$) {
   my ($app, $req, $dest) = @_; weaken $req;

   $dest->{is_member     } = \&is_member;
   $dest->{loc           } = sub { loc( $req, shift, @_ ) };
   $dest->{reference     } = sub { ref $_[ 0 ] };
   $dest->{show_node     } = \&show_node;
   $dest->{str2time      } = \&str2time;
   $dest->{time2str      } = \&time2str;
   $dest->{ucfirst       } = sub { ucfirst $_[ 0 ] };
   $dest->{uri_for       } = sub { $req->uri_for( @_ ), };
   $dest->{uri_for_action} = sub { uri_for_action( $req, @_ ), };
   return;
}

sub table_link ($$$$) {
   return { class => 'table-link windows', hint  => loc( $_[ 0 ], 'Hint' ),
            href  => HASH_CHAR,            name  => $_[ 1 ],
            tip   => $_[ 3 ],              type  => 'link',
            value => $_[ 2 ], };
}

sub to_dt ($;$) {
   my ($dstr, $zone) = @_; $zone //= NUL;

   my $dt = ($zone and $zone ne 'local') ? str2date_time( $dstr, $zone )
                                         : str2date_time( $dstr );

   $zone or $dt->set_time_zone( 'GMT' );

   return $dt;
}

sub uri_for_action ($$;@) {
   my ($req, $action, @args) = @_;

   blessed $req or throw 'Not a request object [_1]', [ $req ];

   my $uri = $action_path_uri_map->{ $action } // $action;

   return $req->uri_for( $uri, @args );
}

sub varchar_data_type (;$$) {
   return { data_type         => 'varchar',
            default_value     => $_[ 1 ] // NUL,
            is_nullable       => FALSE,
            size              => $_[ 0 ] || VARCHAR_MAX_SIZE, };
}

1;

__END__

=pod

=encoding utf-8

=head1 Name

App::Notitia::Util - Functions used in this application

=head1 Synopsis

   use App::Notitia::Util qw( uri_for_action );

   my $uri = uri_for_action $req, $action_path, $args, $params;

=head1 Description

Functions used in this application

=head1 Configuration and Environment

Defines no attributes

=head1 Subroutines/Methods

=item C<assert_unique>

=item C<assign_link>

=item C<authenticated_only>

=item C<bind>

=item C<bind_fields>

=item C<bool_data_type>

=item C<build_navigation>

=item C<build_tree>

=item C<button>

=item C<check_field_js>

=item C<check_form_field>

=item C<clone>

=item C<create_link>

=item C<date_data_type>

=item C<delete_button>

=item C<dialog_anchor>

=item C<encrypted_attr>

=item C<enhance>

=item C<enumerated_data_type>

=item C<field_options>

=item C<foreign_key_data_type>

=item C<gcf>

Greatest common factor

=item C<get_hashed_pw>

=item C<get_salt>

=item C<is_draft>

=item C<is_encrypted>

=item C<iterator>

=item C<js_anchor_config>

=item C<lcm>

Least common muliple

=item C<lcm_for>

LCM for a list of integers

=item C<load_file_data>

=item C<loc>

=item C<localise_tree>

=item C<make_id_from>

=item C<make_name_from>

=item C<make_tip>

=item C<management_link>

=item C<mtime>

=item C<new_salt>

=item C<nullable_foreign_key_data_type>

=item C<nullable_varchar_data_type>

=item C<numerical_id_data_type>

=item C<register_action_paths>

   register_action_paths $action_path => $partial_uri;

Used by L</uri_for_action> to lookup the partial URI for the action path
prior to calling L<uri_for|Web::ComposableRequest::Base/uri_for>

=item C<save_button>

=item C<serial_data_type>

=item C<set_element_focus>

=item C<set_on_create_datetime_data_type>

=item C<show_node>

=item C<slot_claimed>

=item C<slot_identifier>

=item C<slot_limit_index>

=item C<stash_functions>

=item C<table_link>

=item C<to_dt>

=item C<uri_for_action>

   $uri = uri_for_action $request, $action_path, $uri_args, $query_params;

Looks up the action path in the map created by call to L</register_action_path>
then calls L<uri_for|Web::ComposableRequest::Base/uri_for> which is a method
provided by the request object. Returns a L<URI> object reference

=item C<varchar_data_type>

=head1 Diagnostics

None

=head1 Dependencies

=over 3

=item L<strictures>

=item L<Class::Usul>

=item L<Crypt::Eksblowfish::Bcrypt>

=item L<Data::Validation>

=item L<Exporter::Tiny>

=item L<HTTP::Status>

=item L<JSON::MaybeXS>

=item L<Try::Tiny>

=item L<YAML::Tiny>

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
