var cs: [0..numLocales-1] domain(1);

coforall loc in Locales with (ref cs) do
  on loc do
    cs[loc.id] = {0..loc.id};

writeln(cs);
