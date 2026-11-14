// dart2js targets browsers; Node needs the same timer global and explicit args.
globalThis.self = globalThis;
globalThis.dartMainRunner = (main) => main(process.argv.slice(3));
require(process.argv[2]);
