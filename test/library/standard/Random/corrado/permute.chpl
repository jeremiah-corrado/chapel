use Random;

var rs = new randomStream(int, seed=314159);

const doms = ({1..10}, {1..10 by 2}, {1..10 by 2 align 2});

for d in doms {
    const a = [i in d] i,
          b = rs.permute(a);
    writeln(a);
    writeln(b);
    writeln("-----------");
}
