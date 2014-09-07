package Mojolicious::Plugin::Localize;
use Mojo::Base 'Mojolicious::Plugin';
use Mojo::Util qw/squish trim dumper/;
use Mojolicious::Plugin::Config;
use File::Spec::Functions 'file_name_is_absolute';
use List::MoreUtils 'uniq';

$Data::Dumper::Deparse = 1;

# TODO: 'd' is probably better than 'loc'
#       'd' for dictionary lookup

# TODO: Use Mojo::Template directly

# Todo: deal with:
# <%=numsep $g_count %> <%=num $g_count, 'guest', 'guests' %> online.'

our $DEBUG = 0;
our $VERSION = '0.03';

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

    # Localization helper
    $mojo->helper(
      loc => sub {
	my $c = shift;

	# Return complete dictionary in case no parameter is defined
	# This is not documented and may change in further versions
	return $global unless @_;

	my @name = split '_', shift;

	warn 'Look for ' . join('_',  @name) if $DEBUG;

	# Init some variables
	my ($local, $i, $entry, @stack) = ($global, 0);

	my $default_entry = shift if @_ && @_ % 2 != 0;
	my %stash = @_;


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

		my $key = trim $c->include(inline => $index, %stash);

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

	    # Todo: remember default position, even if preferred key was found!

	    # Get default key
	    if ($local->{'-'}) {
	      warn 'There is a default key: ' . $local->{$local->{'-'}} if $DEBUG;

	      # Use the default key
	      unless ($entry) {
		$entry = $local->{$local->{'-'}};
	      }

	      # remember the position for backtracking
	      else {
		push(@stack, [$i, $local->{$local->{'-'}}]);
	      };
	    };
	  };

	  # Forward until found in local
	  if (!$entry && @stack) {
	    ($i, $local) = @{pop @stack};
	  }
	  elsif (!ref ($local = $entry) || ref $local eq 'SCALAR' || ref $local eq 'CODE') {
	    last;
	  };
	};

	# Return entry if it's a string
	unless ($entry) {
	  $c->app->log->warn('No entry found for key ' . join('_',  @name));
	  return $default_entry // '';
	};
	return $$entry if ref $entry eq 'SCALAR';
	return $entry->($c) if ref $entry eq 'CODE';

	# Return template
	return trim $c->include(inline => $entry, %stash);
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
      _  => sub { $_->locale },
      de => {
        welcome => "Willkommen in <%=loc 'name_land' %>!",
        bye => 'Auf Wiedersehen!'
      },
      -en => {
        welcome => "Welcome to <%=loc 'name_land' %>!",
        bye => 'Good bye!'
      },
      App => {
        name => {
          -long => 'Mojolicious',
          short => 'Mojo',
          land  => 'MojoLand'
        }
      }
    }
  };

  # Call dictionary entries from templates
  %= loc 'welcome'


=head1 DESCRIPTION

L<Mojolicious::Plugin::Localize> is a localization framework for
Mojolicious, heavily inspired by Mozilla's L<l20n|http://l20n.org/>.
Instead of being a reimplementation it uses L<Mojo::Template> for string interpolation,
L<Mojolicious::Plugin::Config> for distributed dictionaries and L<Helpers|Mojolicious/helper>
for template functions.

B<Warning!> This is early software and behaviour may change without notifications!


=head1 METHODS

=head2 register

  app->plugin(Localize => {
    dict => {
      _  => sub { $_->locale },
      de => {
        welcome => 'Willkommen!',
        bye => 'Auf Wiedersehen!',
      },
      en => {
        welcome => 'Welcome!',
        bye => 'Good bye!'
      }
    },
    override  => 1,
    resources => ['french.dict', 'polish.dict']
  });

Called when registering the plugin.

Expects a parameter C<dict> containing a localization L<dictionary|/DICTIONARIES>.
Further dictionary files to be loaded can be passed as an array reference
using the C<resources> parameter.

The plugin can be registered multiple times, and defined dictionaries will be merged.

Already existing key definitions won't be overridden in that way,
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

  # Lookup a dictionary entry as a controller method
  my $entry = $c->loc('welcome');

  %# Lookup a dictionary entry in templates
  <%= loc 'welcome' %>
  <%= loc 'welcome', 'Welcome to the site!' %>
  <%= loc 'welcome', user => 'Peter' %>
  <%= loc 'welcome', 'Welcome to the site!', user => 'Peter' %>

Makes a dictionary lookup and returns a string.

Expects a dictionary key, an optional fallback message and optional stash values.


=head2 localize

  $c->localize->locale('de');

Helper object for nested helpers.
L<Mojolicious::Plugin::Localize> loads further plugins establishing nested helpers,
see L<localize.locale|Mojolicious::Plugin::Localize::Locale>.


=head1 DICTIONARIES

Dictionaries can be loaded by registering the plugin either as a passed C<dict> value
or in separated files using the C<resources> parameter.


=head2 Notation

  {
    en => {
      tree => {
        sg => 'Tree',
        pl => 'Trees'
    },
    de => {
      tree => {
        sg => 'Baum',
        pl => 'Bäume'
      }
    }
  }

Dictionaries are nested hash references.
On each level, there is a key that can either lead to a subdictionary
or to a value.
  {
    en => {
      welcome => 'Welcome!'
      greeting => '<%= loc "en_welcome" %> Nice to meet you, <%= $user %>!'
    },
    de => {
      welcome => 'Willkommen!',
      greeting => '<%= loc "de_welcome" %> Schön, Dich zu sehen, <%= $user %>!'
    }
  }

Values may be strings, L<Mojo::Template> strings (with default configuration),
or code references (with the controller object passed when evaluating).

As you see above, values may fetch further dictionary entries using the L<loc|/loc> helper.
To fetch entries from the dictionary using the L<loc|/loc> helper,
the user has to pass the key structure in so-called I<short notation>, by adding
underscores between all keys.
The short notation for the entry C<Bäume> in the first example is C<de_tree_pl>.

  %= loc 'de_tree_pl'
  %# 'Bäume'

The short notation can also be used to add new dictionary entries
using dictionary files or the C<dict> parameter of the plugins registration handler.
The following dictionary definitions are therefore equal:

  {
    de => {
      welcome => 'Willkommen!'
    }
  }

  {
    de_welcome => 'Willkommen!'
  }

There is no limitation for nesting or the order of dictionary entries.


=head2 Preferred Keys

The underscore is a special key, marking preferred keys on the dictionary level,
in case no matching key can be found on that level
(which is the case when a key in short notation is underspecified).

  {
    welcome => {
      _ => 'en',
      de => 'Willkommen!'
      en => 'Welcome!'
    }
  }

In case the key C<welcome_de> is requested with the above dictionary established,
the value C<Willkommen!> will be returned.
But if the underspecified key C<welcome> is requested without a matching key on the
final level, the preferred key C<en> will
be used instead, returning the value C<Welcome!>.

Preferred keys can exist on any level of the nesting and are always called when
there is no matching key as part of the short notation.

Preferred keys may contain the key as a string, a L<Mojo::Template>, an array reference
of keys (in order of preference), or a subroutine returning either a string or an array
reference.

  # The preferred key is 'en'
  _ => 'en'

  # The preferred key is the stash value of 'user_status' (e.g. 'mod' or 'admin')
  _ => '<%= $user_status %>'
  _ => sub { shift->stash('user_status') }

  # The preferred key is 'en', and in case this isn't defined, it's 'de' etc.
  _ => [qw/en de/]
  _ => sub { [qw/en de/] }

The first parameter passed to subroutines is the controller object,
and the local variable C<$_> is set to the L<nested helper object|/localize>,
which eases calls to, for example,
the L<locale|Mojolicious::Plugin::Localize::locale> helper

  # The preferred key is based on the user agent's localization
  _ => sub { $_->locale }

Preferred keys in I<short notation> have a trailing underscore:

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
  # Set the preferred key in short notation


=head2 Default Keys

The dash symbol is a special key, marking default keys on the dictionary level,
in case no matching or preferred key can be found on that level.
They can be given in addition to preferred keys.

  {
    welcome => {
      _   => 'pl',
      '-' => 'en',
      en  => 'Welcome!',
      de  => 'Welcome!'
    }
  }

In case the key C<welcome_de> is requested with the above dictionary established,
the value C<Willkommen!> will be returned. But if the underspecified key C<welcome>
is requested without a matching key on the final level, and the preferred key C<pl>
isn't defined in another dictionary, the default key C<en> will be used instead,
returning the value C<Welcome!>.

Default keys can be alternatively marked with a leading dash symbol.

  {
    welcome => {
      _   => 'pl',
      -en => 'Welcome!',
      de  => 'Welcome!'
    }
  }

To define default keys in I<short notation>, prepend a dash to each subkey in question.

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

In case a key is not found in a nested structure using the L<loc|/loc> helper,
the dictionary lookup will track back to the last branching default key.

For example, if the system looks up the dictionary key C<welcome>,
there is an existing entry for the preferred key C<de> on the first level,
but the processing will stop, as no entry for C<welcome> can be found on the next level.
The system will then track back one level and choose the default key C<en>
instead, where an entry for C<welcome> can be found. The value C<Welcome!> will be returned.

(The system won't test further preferred keys,
but this behaviour might change in the future.)


=head2 Hints and Conventions

L<Mojolicious::Plugin::Localize> let you decide, how to nest your dictionary entries.
For internationalization purposes, it is a good idea to have the language key on the first
level, so you can establish further entries relying on that structure (see, e.g., the example
snippet in L<SYNOPSIS>).

Dictionary keys should always be lower case, and plugins,
that provide their own dictionaries, should prefix their keys with a namespace
(e.g. the plugin's name) in camel case,
to prevent clashes with other dictionary entries.
For example the C<welcome> message for this plugin should be named C<Localize_welcome>.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Localize


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014, L<Nils Diewald|http://nils-diewald.de/>.

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

=cut
