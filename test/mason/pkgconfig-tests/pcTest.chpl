private use List;
use MasonUpdate;
use MasonUtils;
use TOML;
use FileSystem;

proc test(goodLock: string, tf: string) {
  // In order to avoid updating the .good/lock file every release we store
  // a sentinel 'CHPL_CUR_FULL' representing the current Chapel version. Before
  // passing anything to updateLock we need to replace that sentinel with the
  // actual current version.

  const currentVersion = getChapelVersionStr();

  // file.good -> file.lock
  const lf = goodLock.replace('good', 'lock');
  var temp = open(lf, ioMode.cw);
  {
    var w = temp.writer(locking=false);
    for line in openReader(goodLock, locking=false).lines() do
      w.write(line.replace('CHPL_CUR_FULL', currentVersion));
    w.close();
  }

  var configs = updateLock(true, tf=tf, lf=temp.path);
  var lock = open(temp.path, ioMode.r);
  var lockFile = parseToml(lock);
  writeln(lockFile);
  remove(lf);
  temp.close();
  lock.close();
}
