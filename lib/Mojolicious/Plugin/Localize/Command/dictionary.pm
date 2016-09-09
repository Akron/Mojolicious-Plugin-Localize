package Mojolicious::Plugin::Localize::Command::dictionary;
use Mojo::Base 'Mojolicious::Command';
use Mojo::Util qw/quote/;
use Mojo::Date;

has description => 'Generate dictionary files for Localize (2)';
has usage       => sub { shift->extract_usage };

our $SPECIAL = '!SPECIAL!';

sub run {
  my $self = shift;
  my $input = shift;
  my $output = shift;

  my $app = $self->app;

  my $dict = $app->localize->dictionary;

  print '# Dictionary template generated ' . Mojo::Date->new(time) . "\n\n";

  my $c = $app->build_controller;

  # Setting an unlikely locale
  $c->stash('localize.locale' => [$SPECIAL]);

  # Recursive investigate the dictionary
  print "{\n";
  _investigate($c, $dict, [], 0, $input, $output);
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
  my ($c, $dict, $path, $level, $input, $output) = @_;

  if (!ref $dict || ref $dict eq 'SCALAR' || ref $dict eq 'CODE') {

    # Check elements of the path
    my @elements = @{$path}[0..$level - 1];

    return unless grep /\*/, @elements;

    # Join the missing key
    my $key = join('_', map { $_ eq '*' ? $output : $_ } @elements);

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
  local $_ = $c->localize;

  # Define the example branch
  my $locale_example;

  # There is a locale branch
  if ($dict->{_} && $dict->{_}->($c)->[0] eq $SPECIAL) {

    # Define the output for the path
    $path->[$level] = '*';

    # The output already exists
    if ($dict->{$output}) {
      $path->[$level] = $output;
      $locale_example = $output;
    }

    # The input example branch exists
    elsif ($dict->{$input}) {
      $locale_example = $input;
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

    # Follow the locale
    _investigate(
      $c,
      $dict->{$locale_example},
      $path,
      $level + 1,
      $input,
      $output
    );
  };


  # FOLLOW ALL KEYS!
  foreach (grep { $_ ne '-' && $_ ne '_' } keys %$dict) {
    $path->[$level] = $_;
    _investigate($c, $dict->{$_}, $path, $level + 1, $input, $output);
  };
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
