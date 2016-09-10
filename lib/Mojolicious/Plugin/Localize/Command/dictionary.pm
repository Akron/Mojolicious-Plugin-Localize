package Mojolicious::Plugin::Localize::Command::dictionary;
use Mojo::Base 'Mojolicious::Command';
use Mojo::Util qw/quote/;
use Mojo::Date;

has description => 'Generate dictionary files for Localize (2)';
has usage       => sub { shift->extract_usage };

our $SPECIAL = '!SPECIAL!';

use constant DEBUG => $ENV{MOJO_LOCALIZE_DEBUG} || 0;

has [qw/input output controller/];

sub run {
  my $self = shift;

  $self->input(shift);
  $self->output(shift);

  my $app = $self->app;

  my $dict = $app->localize->dictionary;

  print '# Dictionary template generated ' . Mojo::Date->new(time) . "\n\n";

  $self->controller($app->build_controller);

  # Setting an unlikely locale
  $self->controller->stash('localize.locale' => [$SPECIAL]);

  # Recursive investigate the dictionary
  print "{\n";
  $self->_investigate($dict, [], 0);
  print "};\n";

  # Iterate over all dictionary entries.
  # If a sub returns '::LOCALIZE-THIS::', it's a localizing
  # branch in the tree and needs a new 'pl' key in the path,
  # with the default path as the pattern.
  # Otherwise follow all branches.

  # Unknown command
  print $self->usage and return;
};

sub _investigate {
  my ($self, $dict, $path, $level) = @_;

  if (!ref $dict || ref $dict eq 'SCALAR' || ref $dict eq 'CODE') {

    # Check elements of the path
    my @elements = @{$path}[0..$level - 1];

    # Key is not localed
    return unless grep /[\*\+]/, @elements;

    # Join the missing key
    my $key = join('_', map { $_ eq '*' ? $self->output : $_ } @elements);

    print '  # ' . quote($key) . ' => ';

    # Print example entry
    if (!ref $dict) {
      print quote($dict) . ",\n";
    }

    # Print scalar value
    elsif (ref $dict eq 'SCALAR') {
      print '\\' . quote($$dict) . ",\n";
    }

    # Print sub
    elsif (ref $dict eq 'CODE') {
      print "sub { ... },\n";
    };

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

    # Define the output for the path
    $path->[$level] = '*';

    # The output already exists
    # if (exists $dict->{$output}) {
      #$path->[$level] = '+';
      #   $locale_example = $output;
    # };

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
      warn 'No example path defined for locale branch ...';
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

1;

__END__

=pod

=encoding utf8

=head1 NAME

Mojolicious::Plugin::Localize::chi - Interact with CHI caches

=head1 SYNOPSIS

=head1 DESCRIPTION


May be use generate command with generate dictionary!

  $ perl script/myapp localize en pl

or may be use generate command with generate dictionary!

  $ perl script/myapp generate dictionary en pl

This will print out a dictionary file in short notation
with locales set to 'pl' and based on the dictionary entries for 'en'.

{
  _  => sub { $_->locale },
  -de => {
    welcome => "Willkommen in <%=loc 'App_name' %>!",
    bye => 'Auf Wiedersehen!'
  },
  en => {
    welcome => "Welcome to <%=loc 'App_name' %>!",
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

Applied to the aforementioned dictionary, this will create the following output.

{
  # pl_welcome => "Welcome to <%=loc 'App_name' %>!",
  # pl_bye => 'Good bye!'
}
