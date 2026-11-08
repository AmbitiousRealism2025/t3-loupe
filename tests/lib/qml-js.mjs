// Loads a QML JavaScript resource (".pragma library") into a node vm context,
// so tests exercise the exact file the shell loads.
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import vm from "node:vm";

export function loadQmlJs(file) {
  const context = vm.createContext({});
  const source = readFileSync(file, "utf8")
    .split("\n")
    .map((line) => {
      if (/^\s*\.pragma\s+library\s*;?\s*$/.test(line)) return "";
      // `.import "Other.js" as Name`: a sibling library, loaded the same way.
      const imported = /^\s*\.import\s+"([^"]+\.js)"\s+as\s+(\w+)\s*;?\s*$/.exec(line);
      if (imported) {
        context[imported[2]] = loadQmlJs(join(dirname(file), imported[1]));
        return "";
      }
      if (/^\s*\./.test(line)) throw new Error(`unsupported QML JS directive in ${file}: ${line}`);
      return line;
    })
    .join("\n");
  vm.runInContext(source, context, { filename: file });
  return context;
}
