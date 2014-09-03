package Mojolicious::Plugin::Localize;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util qw/squish trim dumper/;
use Mojolicious::Plugin::Config;
use File::Spec::Functions 'file_name_is_absolute';
use List::MoreUtils 'uniq';

$Data::Dumper::Deparse = 1;

# Todo: Support backtracking!

# TODO: 'd' is probably better than 'loc'
#       'd' for dictionary lookup

# TODO: find out the template parameters for Mojo::Template
# my $renderer = $mojo->renderer;
# warn $mojo->dumper($renderer->handlers->{$renderer->default_handler}->($renderer));

# Todo: deal with:
# There <%=num $g_count 'is', 'are' %> currently
# <%=numsep $g_count %> <%=num $g_count, 'guest', 'guests' %> online.'

our $DEBUG = 0;
our $VERSION = '0.02';

# Warning: This only works for default EP templates
our $TEMPLATE_INDICATOR = qr/(?:^\s*\%)|<\%/m;


# Unflatten short notation
sub _unflatten {
  my ($key, $dict) = @_;
  my $k = $$key;
  my $g_hash = $dict->{$k};

  # Check for preferred key
  if (substr($k, -1, 1) eq '_') {
    $g_hash = { _  => $g_hash };
    chop $k;
  };

  # Build verbose tree
  $g_hash = { $1 => $g_hash } while $k =~ s/_([^_]+)$//;

  # Set root key
  $$key = $k;
  $dict->{$k} = $g_hash;
};


# Store value as string or code reference
sub _store {
  my $value = $_[0];

  # Is template - store as reference
  return $value if ref $value || $value =~ $TEMPLATE_INDICATOR;
  return \$value;
};


# Merge dictionaries
sub _merge {
  my ($self, $global, $dict, $override) = @_;

  # Iterate over all keys
  foreach my $k (keys %$dict) {

    warn qq!Merge key "$k"! if $DEBUG;

    # This is a short notation key
    if (index($k, '_') > 0) {
      warn "Unflatten $k to ... " if $DEBUG;
      _unflatten(\$k, $dict);
      warn "... " . dumper $k if $DEBUG;
    }

    # Set preferred key
    elsif ($k eq '_') {

      # If override or not set yet, set the new preferred key
      if ($override || !defined $global->{_}) {
	warn 'Override _' if $DEBUG;
	$global->{_} = $dict->{_};
      };
      next;
    };

    # This is a default key
    if (index($k, '-') == 0) {
      my $standalone = 0;

      # This is a prefixed default key
      if (length $k > 1) {
	warn 'Set a prefixed default key' if $DEBUG;
	$k = substr($k, 1);
	$dict->{$k} = delete $dict->{"-$k"};
      }

      # This is a standalone default key
      else {
	warn 'Set a standalone default key' if $DEBUG;
	$k = $dict->{'-'};
	$standalone = 1;
      };

      # If override or not set yet, set the new default key
      if ($override || !defined $global->{'-'}) {
	warn 'Override default key' if $DEBUG;
	$global->{'-'} = $k;
      };

      next if $standalone;
    }

    # Insert key - if it not yet exists
    if (!$global->{$k}) {

      # Merge the tree
      if (ref $dict->{$k} eq 'HASH') {
	$self->_merge($global->{$k} = {}, $dict->{$k}, $override);
      }

      # Store the plain value
      else {
	$global->{$k} = _store($dict->{$k});
      };
    }

    # Merge key
    elsif (ref($global->{$k}) eq ref($dict->{$k}) && ref($global->{$k}) eq 'HASH') {
      $self->_merge($global->{$k}, $dict->{$k}, $override);
    }

    # Override global and store the plain value
    elsif ($override) {
      $global->{$k} = _store($dict->{$k});
    };
  };
};


# Register plugin
sub register {
  my ($self, $mojo, $param) = @_;

  state $global   = {};
  state $template = {};
  state $init = 0;

  my (@dict, @resources);
  @dict      = ($param->{dict})       if $param->{dict};
  @resources = @{$param->{resources}} if $param->{resources};

  # Not yet initialized
  unless ($init) {

    # Load parameter from config file
    if (my $c_param = $mojo->config('Localize')) {

      # Prefer the configuration dictionary
      if ($c_param->{dict}) {
	push @dict, $c_param->{dict};
      };

      # Prefer the configuration override parameter
      $param->{override} = $c_param->{override} if $c_param->{override};

      # Add configuration resources
      if ($c_param->{resources}) {
	unshift @resources, @{$param->{resources}};
      };
    };

    # Load default helper
    $mojo->plugin('Localize::Number');
    $mojo->plugin('Localize::Locale');

    $mojo->helper(
      loc_for => sub {
	my $c = shift;
	my $loc_for;
	unless ($loc_for = $c->stash('localize.for')) {
	  $c->stash('localize.for' => $loc_for = []);
	};
	push(@$loc_for, \@_);
      }
    );

    # Localization helper
    $mojo->helper(
      loc => sub {
	my $c = shift;
	return $global unless @_;

	my $name = shift;
	my @name = split '_', $name;

	# Template dictionary
	if (ref $_[-1] eq 'CODE' && !$template->{$name}) {
	  my $snippet = pop;

	  warn 'Add template entries' if $DEBUG;

	  # Merge dictionary hash
	  $self->_merge($global, $_[0], 0) if $_[0];

	  # Run template snippet
	  $snippet->();

	  # Add 'loc_for' dictionary entries
	  foreach (@{$c->stash('localize.for') || []}) {
	    warn '>>>>>' . $_->[1] if $DEBUG;
	    $self->_merge($global, { $_->[0] => $_->[1] }, 0);
	  };

	  $template->{$name} = 1;
	};

	warn 'Look for ' . join('_',  @name) if $DEBUG;

	my ($local, $i, $entry) = ($global, 0);

	# Search for key in infinite loop
	while () {

	  # Get the key from the local dictionary
	  $entry = $name[$i] ? $local->{$name[$i]} : undef;

	  if ($DEBUG) {
	    warn qq!Search key $i: ! . ($name[$i] // '?') . ' -> ' . ($entry // '');
	  };

	  # Entry was found
	  if ($entry) {

	    # Forward to next subkey
	    $i++;
	  }

	  # No entry found
	  else {
	    warn 'No entry found' if $DEBUG;

	    # Get preferred keys
	    if ($local->{_}) {

	      warn 'There is a preferred key' if $DEBUG;

	      my $index = $local->{_};

	      # Preferred key is a template
	      unless (ref $index) {

		my $key = trim $c->include(inline => $index);

		# Store value
		$entry = $local->{$key};

		warn '> Template: ' . $key . ' -> ' . $entry if $DEBUG;
	      }

	      # Preferred key is a subroutine
	      elsif (ref $index eq 'CODE') {
		local $_ = $c->localize;
		my $preferred = $index->($c);

		for (ref $preferred ? @$preferred : $preferred) {
		  last if $entry = $local->{$_};
		};
		warn '> Subroutine: ' .
		  (ref $preferred ? join(',', @$preferred) : $preferred) .
		    ' -> ' . ($entry // '') if $DEBUG;
	      }

	      # Preferred key is an array
	      elsif (ref $index eq 'ARRAY') {
		foreach (@$index) {
		  last if $entry = $local->{$_};
		};
		warn '> Array: ' . join(',', @$index) . ' -> ' . $entry if $DEBUG;
	      };
	    };

	    # Get default key
	    if (!$entry && $local->{'-'}) {
	      warn 'There is a default key: ' . $local->{$local->{'-'}} if $DEBUG;
	      $entry = $local->{$local->{'-'}};
	    };
	  };

	  # Forward until found in local
	  last if !ref ($local = $entry) || ref $local eq 'SCALAR' || ref $local eq 'CODE';
	};

	# Return entry if it's a string
	return '' unless $entry;

	return $$entry if ref $entry eq 'SCALAR';



	if (ref $entry eq 'CODE') {
	  warn dumper $entry if $DEBUG;
	  return $entry->() ;
	};

	# Return template
	return trim $c->include(inline => $entry);
      }
    );

    $init = 1;
  };

  # Merge dictionary resources
  if (@resources) {

    # Create config loader
    my $config_loader = Mojolicious::Plugin::Config->new;
    my $home = $mojo->home;

    # Load files
    foreach my $file (uniq @resources) {
      $file = $home->rel_file($file) unless file_name_is_absolute $file;

      if (-e $file) {
	unshift @dict, $config_loader->load($file, undef, $mojo);
      }
      else {
	$mojo->log->warn(qq!Unable to load dictionary file "$file"!);
      };
    };
  };

  # Merge dictionary hashes
  $self->_merge($global, $_, $param->{override}) foreach @dict;
};


1;


__END__

=pod

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Localize - Localization Framework for Mojolicious


=head1 SYNOPSIS

  # Register the plugin with a defined dictionary
  plugin  Localize => {
    dict => {
      name => {
        -long => 'Mojolicious',
        short => 'Mojo',
        land  => 'MojoLand'
      },
      welcome => {
        _  => sub { $_->locale },
        de => "Willkommen in <%=loc 'name_land' %>!",
        en => "Welcome to <%=loc 'name_land' %>!"
      }
    }
  };

  # Call dictionary entries from templates
  %= loc 'welcome'


=head1 DESCRIPTION

L<Mojolicious::Plugin::Localize> is a localization framework for
Mojolicious, heavily inspired by Mozilla's L<l20n|http://l20n.org/>.
Instead of being a reimplementation it uses L<Mojo::Template> for string interpolation,
L<Mojolicious::Plugin::Config> for distributed dictionaries and Mojolicious' helpers
for template functions.

B<Warning!> This is early software and behaviour may change without notifications!

=head1 METHODS

=head2 register

  app->plugin(Localize => {
    dict => {
      welcome => {
        _  => sub { $_->locale },
        de => 'Willkommen!',
        en => 'Welcome!'
      }
    },
    override  => 1,
    resources => ['french.dict', 'polish.dict']
  });

Called when registering the plugin.

Expects a parameter C<dict> containing a L<dictionary|/DICTIONARIES>.
Further dictionary files to be loaded can be passed as an array reference
using the C<resources> parameter.

The plugin can be registered multiple times, and defined dictionaries will be merged.

Already existing key definitions won't be overwritten in that way,
unless an additional C<override> parameter is set to a C<true> value.
Dictionary entries from resource files, on the other hand, will always override,
so the order of the given array is of relevance.

All parameters can be set either on registration or in a configuration file
with the key C<Localize> (loaded only on first registration).


=head1 HELPERS

In addition to the listed helpers,
L<Mojolicious::Plugin::Localize> loads further helpers by default,
see L<num|Mojolicious::Plugin::Localize::Number> and
L<locale|Mojolicious::Plugin::Localize::Locale>.


=head2 loc

  # Lookup dictionary entry from controller
  my $entry = $c->loc('welcome');

  %# Lookup dictionary entry in templates
  <%= loc 'welcome' %>

  %# Lookup and provide dictionary entries in templates
  %= loc 'welcome', begin
  %   loc_for '-en_welcome', begin
  Welcome to our site!
  %   end
  % end

Makes a dictionary lookup and returns a string.

The first parameter is the dictionary key to look up.
Optionally a C<begin> block may follow, providing several
translations directly in the template (see L<loc_for|/loc_for>).
Definitions on the dictionary structure (e.g. to define preferred and default keys)
may precede the C<begin> block.


=head2 loc_for

  %# In templates
  %= loc 'welcome', { welcome_ => sub { $_->locale } }, begin
  %   loc_for welcome_de => begin
  Herzlich willkommen auf unserer Seite, <%= stash 'user' %>!
  %   end
  %   loc_for 'welcome_-en' => begin
  Welcome to our site, <%= stash 'user' %>!
  %   end
  % end

Define dictionary entries in templates.

In case, the L<loc|/loc> helper starts a C<begin> block,
several translations may be defined directly in the template,
that are merged with the dictionary
on the first compilation of the template.

The helper expects a defined key in L<short notation|/Short Notation>
and a block containing the dictionary value.

This comes in handy for template design, so the designer knows at least
rougly the length and content of a text block to layout.
However, defining a dictionary this way is I<not recommended>,
as dictionary entries in this way are unknown on application start
(and therefore inaccessible to the C<localize> command!

B<WARNING>: Never use C<$name> stash values in C<loc_for> blocks, as they will
be compiled only once with the first rendering. Use C<stash('name')> instead!


=head2 localize

  $c->localize->locale('de');

Helper object for nested helpers.
L<Mojolicious::Plugin::Localize> loads further plugins establishing nested helpers,
see L<localize.locale|Mojolicious::Plugin::Localize::Locale>.


=head1 DICTIONARIES

=head2 Short Notation

The underscore notation can also be used to flatten nesting dictionary structures.
The following definitions are therefore equal:

  {
    welcome => {
      de => 'Willkommen!'
    }
  }

  {
    welcome_de => 'Willkommen!'
  }


=head2 Preferred Keys

The underscore is a special key, marking preferred keys on the dictionary level,
in case no matching key can be found.

  {
    welcome => {
      _ => 'en',
      de => 'Willkommen!'
      en => 'Welcome!'
    }
  }

In case the key C<welcome_de> is requested with the above dictionary established,
the value C<Willkommen!> will be returned. But if the underspecified key C<welcome>
is requested without a matching key on the final level, the preferred key C<en> will
be used instead, returning the value C<Welcome!>.

Preferred keys may contain the key as a string, a template, an array reference
of keys (in order of preference), or a subroutine returning a string or an array
reference.

  # The preferred key is 'en'
  _ => 'en'

  # The preferred key is the stash value of 'user_status' (e.g. 'mod' or 'admin')
  _ => '<%= $user_status %>'
  _ => sub { shift->stash('user_status') }

  # The preferred key is 'en', and in case this isn't defined, it's 'de'
  _ => [qw/en de/]
  _ => sub { [qw/en de/] }

The first parameter passed to subroutines is the controller object.
The local variable C<$_> is set to the L<nested helper object|/localize>,
which eases calls to, for example,
the L<locale|Mojolicious::Plugin::Localize::locale> helper.

  # The preferred key is based on the requested languages
  _ => sub { $_->locale }

Preferred keys in short notation have a trailing underscore:

  {
    greeting => {
      _ => sub { $_->locale },
      en => 'Hello!',
      de => 'Hallo!'
    }
  }
  # Set the preferred key in nested notation

  {
    greeting_ => sub { $_->locale }
    greeting_en => 'Hello!',
    greeting_de => 'Hallo!'
  }
  # Same as above in short notation


=head2 Default Keys

Default keys are marked with a leading dash symbol and can
be given in addition to preferred keys.
They will be triggered, whenever no direct access is given and no
preferred key matches.

  {
    welcome => {
      _   => 'pl',
      -en => 'Welcome!',
      de  => 'Welcome!'
    }
  }

In case the key C<welcome_de> is requested with the above dictionary established,
the value C<Willkommen!> will be returned. But if the underspecified key C<welcome>
is requested without a matching key on the final level, and the preferred key C<pl> 
isn't defined in another dictionary, the default key C<en> will be used instead,
returning the value C<Welcome!>.

To define a default key separately, use the single dash key.

  {
    welcome => {
      _   => 'pl',
      '-' => 'en',
      en  => 'Welcome!',
      de  => 'Welcome!'
    }
  }
  # This is the same dictionary entry as above

To define default keys in short notation, prepend a dash to the subkey in question.

  {
    'welcome_-en' => 'Welcome!',
    'welcome_de'  => 'Willkomen!'
  }


=head2 Backtracking

  {
    _ => [qw/de fr en/],
    de => {
      bye => 'Auf Wiedersehen!'
    },
    fr => {
      welcome => 'Bonjour!',
      bye => 'Au revoir!'
    },
    -en => {
      welcome => 'Welcome!',
      bye => 'Good bye!'
    }
  }

In case a preferred key is not found in a nested structure,
the dictionary lookup will track back default keys.

For example, if the system looks up the dictionary key C<welcome>,
there is an existing entry for the preferred key C<de> on the first level,
but the processing will stop, as no entry for C<welcome> can be found.
The system will then track back one level and choose the default key C<en>
instead. The system won't test further preferred keys.

B<BACKTRACKING IS NOT YET SUPPORTED!>


=head2 Hints and Conventions

L<Mojolicious::Plugin::Localize> let you decide, how to nest your dictionary entries.
For internationalization purposes, it is a good idea to have the language key on the first
level, so you can establish further entries relying on that structure (see, e.g., the example
snippet in L<loc|/loc>).

Dictionary keys should always be lower case.

Plugins, that provide their own dictionaries, should prefix their keys with the plugin's name,
with the first letter in upper case, to prevent clashes with other dictionary entries.
For example the welcome message for this plugin should be named C<Localize_welcome>.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Localize


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

=cut
