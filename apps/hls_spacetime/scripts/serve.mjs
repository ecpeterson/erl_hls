/** Local, read-only viewer server. Binds loopback; never accepts uploads. */
import http from "node:http";
import { readFile, stat } from "node:fs/promises";
import { resolve, sep, extname } from "node:path";
import { fileURLToPath } from "node:url";
const webRoot = fileURLToPath(new URL("../web/", import.meta.url));
const types = {
  ".html": "text/html; charset=utf-8",
  ".js": "text/javascript; charset=utf-8",
  ".css": "text/css; charset=utf-8",
  ".json": "application/json",
};

/** Honor explicit encoding rejection; prepared gzip is an optional transport. */
function acceptsGzip(header) {
  const encodings = new Map(
    header.split(",").map((entry) => {
      const [name, ...parameters] = entry.trim().toLowerCase().split(";");
      const q = parameters.find((p) => p.trim().startsWith("q="));
      return [name, q === undefined ? 1 : Number(q.trim().slice(2))];
    }),
  );
  return (encodings.get("gzip") ?? encodings.get("*") ?? 0) > 0;
}

/** Serve assets from the repository and saved data from an explicit trusted
 * directory. Request paths cannot escape either selected root. */
export function createViewerServer(dataDirectory = resolve(webRoot, "data")) {
  return http.createServer(async (req, res) => {
    try {
      const pathname = decodeURIComponent(
        new URL(req.url, "http://localhost").pathname,
      );
      const isData = pathname.startsWith("/data/");
      const root = resolve(isData ? dataDirectory : webRoot);
      const suffix = isData ? pathname.slice("/data".length) : pathname;
      const path = resolve(root, "." + suffix);
      if (path !== root && !path.startsWith(root + sep))
        throw Error("outside root");
      const target = (await stat(path)).isDirectory()
        ? resolve(path, "index.html")
        : path;
      const original = await stat(target, { bigint: true });
      let source = target,
        metadata = original,
        encoding = null;
      if (acceptsGzip(req.headers["accept-encoding"] ?? "")) {
        try {
          const compressed = await stat(`${target}.gz`, { bigint: true });
          if (compressed.isFile() && compressed.mtimeNs >= original.mtimeNs) {
            source = `${target}.gz`;
            metadata = compressed;
            encoding = "gzip";
          }
        } catch {
          /* Prepared compression is optional; the raw asset stays valid. */
        }
      }
      // Revalidate mutable paths cheaply. Browser-side content hashes remain the
      // integrity authority; this weak validator is only an HTTP cache hint.
      const etag = `W/"${metadata.ino}-${metadata.size}-${metadata.mtimeNs}-${metadata.ctimeNs}-${encoding ?? "raw"}"`;
      const headers = {
        "Content-Type": types[extname(target)] || "application/octet-stream",
        "Cache-Control": "private, no-cache",
        Vary: "Accept-Encoding",
        ETag: etag,
        "X-Content-Type-Options": "nosniff",
        ...(encoding ? { "Content-Encoding": encoding } : {}),
      };
      if (req.headers["if-none-match"] === etag) {
        res.writeHead(304, headers);
        res.end();
        return;
      }
      res.writeHead(200, {
        ...headers,
        "Content-Length": String(metadata.size),
      });
      res.end(req.method === "HEAD" ? undefined : await readFile(source));
    } catch {
      res.writeHead(404, { "Content-Type": "text/plain" });
      res.end("Not found");
    }
  });
}

/** Later repeated options win; the default serves the existing ignored web/data. */
export function parseArguments(args) {
  const options = { port: Number(process.env.PORT || 4173) };
  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--help") return { help: true };
    const name = args[i];
    if (!["--data", "--port"].includes(name) || !args[i + 1])
      throw Error(`Unknown/incomplete option: ${name}`);
    const value = args[++i];
    if (name === "--data") options.data = resolve(value);
    else options.port = Number(value);
  }
  if (
    !Number.isInteger(options.port) ||
    options.port < 0 ||
    options.port > 65535
  )
    throw Error("Invalid port");
  return options;
}

if (
  process.argv[1] &&
  resolve(process.argv[1]) === fileURLToPath(import.meta.url)
) {
  try {
    const options = parseArguments(process.argv.slice(2));
    if (options.help)
      console.log("npm start -- [--data SAVED_VIEW_DIRECTORY] [--port PORT]");
    else {
      const server = createViewerServer(options.data);
      server.listen(options.port, "127.0.0.1", () =>
        console.log(`Local: http://127.0.0.1:${server.address().port}`),
      );
      process.on("SIGTERM", () => server.close());
      process.on("SIGINT", () => server.close());
    }
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
