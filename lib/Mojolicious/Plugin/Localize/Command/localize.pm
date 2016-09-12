package Mojolicious::Plugin::Localize::Command::localize;
use Mojo::Base 'Mojolicious::Command';
use Mojo::Util qw/quote/;
use Mojo::Date;

has description => 'Generate dictionary files for Localize';
has usage       => sub { shift->extract_usage };

our $SPECIAL = '!SPECIAL!'; # Special locale

use constant DEBUG => $ENV{MOJO_LOCALIZE_DEBUG} || 0;

has [qw/input output controller/];


# Generate dictionary template
sub run {
  my $self = shift;

  $self->input(shift);
  $self->output(shift);

  # Unknown command
  unless ($self->input && $self->output) {
    print $self->usage and return;
  };

  # Initialize key store
  $self->{keys} = {};

  my $app = $self->app;

  # Get generated dictionary
  my $dict = $app->localize->dictionary;

  print '# Dictionary template generated ' . Mojo::Date->new(time) . "\n\n";

  # Set controller
  $self->controller($app->build_controller);

  # Setting an unlikely locale
  $self->controller->stash('localize.locale' => [$SPECIAL]);

  # Recursive investigate the dictionary
  $self->_investigate($dict, [], 0);

  print "{\n";
  $self->_filter->_print;
  print "};\n";
};


# Investigate dictionary entry and check for usage
sub _investigate {
  my ($self, $dict, $path, $level) = @_;

  if (!ref $dict || ref $dict eq 'SCALAR' || ref $dict eq 'CODE') {

    # Check elements of the path
    my @elements = @{$path}[0..$level - 1];

    # Key is not localed
    return unless grep /[\*\+]/, @elements;

    # Join the missing key
    my $key = join('_', @elements);

    $self->{keys}->{$key} = $dict;

    return;
  }

  elsif (ref $dict eq 'ARRAY') {
    warn 'Arrays are not valid dictionary values';
    return;
  };

  # Set local $_ to nested helber for preferred subroutines
  local $_ = $self->controller->localize;

  # Define the example branch
  my $locale_example;

  # There is a locale branch
  if ($dict->{_} && $dict->{_}->($self->controller)->[0] eq $SPECIAL) {

    # The output already exists
    if (exists $dict->{$self->output}) {
      $path->[$level] = '+';
      $locale_example = $self->output;

      if (DEBUG) {
        warn '[DICT] Locale branch at path ' .
          quote(_key($path, $level + 1)) . ' and level [' . $level . ']';
      };

      # Follow the locale
      $self->_investigate(
        $dict->{$locale_example},
        $path,
        $level + 1
      );
    };

    # Define the output for the path
    $path->[$level] = '*';

    # The input example branch exists
    if ($dict->{$self->input}) {
      $locale_example = $self->input;
    }

    # A default branch exists
    elsif ($dict->{'-'} && $dict->{$dict->{'-'}}) {
      $locale_example = $dict->{'-'};
    };

    # Example path is missing - can't follow!
    unless ($locale_example) {
      warn '[DICT] No example path defined for locale branch ' .
        quote(_key($path, $level + 1)) if DEBUG;
      return;
    };

    if (DEBUG) {
      warn '[DICT] Locale branch at path ' .
        quote(_key($path, $level + 1)) . ' and level [' . $level . ']';
    };

    # Follow the locale
    $self->_investigate(
      $dict->{$locale_example},
      $path,
      $level + 1
    );
  };


  # FOLLOW ALL KEYS!
  foreach (grep { $_ ne '-' && $_ ne '_' } keys %$dict) {
    $path->[$level] = $_;
    $self->_investigate($dict->{$_}, $path, $level + 1);
  };
};


# Return the current key
sub _key {
  return join('_', @{$_[0]}[0..$_[1] - 1])
};


# Filter all locale keys already defined
sub _filter {
  my $self = shift;

  # Iterate over all locale given keys
  foreach (grep { index($_, '+') >= 0 } keys %{$self->{keys}}) {

    # Delete all given keys
    delete $self->{keys}->{$_};

    # Delete all keys locale keys that are not already given
    $_ =~ tr/\+/\*/;
    delete $self->{keys}->{$_};
  };

  return $self;
};


# Print out all keys
sub _print {
  my $self = shift;

  my $out = $self->output;

  # Iterate over all stored keys
  while (my ($key, $value) = each %{$self->{keys}}) {

    $key =~ s/\*/$out/g;
    print '  # ' . quote($key) . ' => ';

    # Print example entry
    if (!ref $value) {
      print quote($value) . ",\n";
    }

    # Print scalar value
    elsif (ref $value eq 'SCALAR') {
      print '\\' . quote($$value) . ",\n";
    }

    # Print sub
    elsif (ref $value eq 'CODE') {
      print "sub { ... },\n";
    };
  };

  return $self;
};


1;

__END__

=pod

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Localize::Command::localize - Generate dictionary files for Localize

=head1 SYNOPSIS

  usage: perl app.pl localize <base_lang> <out_lang>

    perl app.lp localize en pl


=head1 DESCRIPTION

Generates a localized dictionary template based on an existent
dictionary.

Given the following merged dictionary of an application:

  {
    _ => sub { $_->locale },
    de => {
      welcome => 'Willkommen!',
      thankyou => 'Danke!'
    },
    fr => {
      thankyou => 'Merci!'
    },
    -en => {
      welcome => 'Welcome!',
      thankyou => 'Thank you!',
    },
    MyPlugin => {
      bye => {
        _ => sub { $_->locale },
        de => 'Auf Wiedersehen!',
        en => 'Good bye!'
      },
      user => {
        _ => sub { $_->locale },
        de => 'Nutzer'
      }
    }
  }

To create a translation template for the locale french based on all
entries of the english locale, call ...

  $ perl app.pl localize en fr

The created dictionary template in short notation will look like this:

  {
    # "fr_welcome" => \"Welcome!",
    # "MyPlugin_bye_fr" => \"Good Bye!",
  };


=head1 ATTRIBUTES

L<Mojolicious::Plugin::Localize::Command::localize> inherits all attributes
from L<Mojolicious::Command> and implements the following new ones.


=head2 description

  my $description = $localize->description;
  $localize = $localize->description('Foo!');

Short description of this command, used for the command list.


=head2 usage

  my $usage = $localize->usage;
  $localize = $localize->usage('Foo!');

Usage information for this command, used for the help screen.


=head1 METHODS

L<Mojolicious::Plugin::Localize::Command::localize> inherits all methods from
L<Mojolicious::Command> and implements the following new ones.


=head2 run

  $localize->run;

Run this command.


=head1 DEPENDENCIES

L<Mojolicious>.


=head1 AVAILABILITY

  https://github.com/Akron/Mojolicious-Plugin-Localize


=head1 COPYRIGHT AND LICENSE

Copyright (C) 2014-2016, L<Nils Diewald||http://nils-diewald.de>.

This program is free software, you can redistribute it
and/or modify it under the terms of the Artistic License version 2.0.

The documentation is based on L<Mojolicious::Command::eval>,
written by Sebastian Riedel.

=cut
