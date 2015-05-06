__END__

numf => sub {
  my $c = shift;
  $c->localize->dec_sep
  $c->localize->mill_sep
}

=pod

Quote from: http://search.cpan.org/~toddr/Locale-Maketext-1.26/lib/Locale/Maketext.pod :

>> Remember to ask your translators about numeral formatting in their language, so that you can override the numf method as appropriate. Typical variables in number formatting are: what to use as a decimal point (comma? period?); what to use as a thousands separator (space? nonbreaking space? comma? period? small middot? prime? apostrophe?); and even whether the so-called "thousands separator" is actually for every third digit -- I've heard reports of two hundred thousand being expressible as "2,00,000" for some Indian (Subcontinental) languages, besides the less surprising "200 000", "200.000", "200,000", and "200'000". Also, using a set of numeral glyphs other than the usual ASCII "0"-"9" might be appreciated, as via tr/0-9/\x{0966}-\x{096F}/ for getting digits in Devanagari script (for Hindi, Konkani, others). <<
