import { loadPreparedRender } from "./prepared-loader.js";

/** One bounded preparation load per worker; the owner terminates on abort/finish. */
self.onmessage = async ({ data }) => {
  try {
    const result = await loadPreparedRender({
      ...data,
      progress: (progress) => self.postMessage({ progress }),
    });
    self.postMessage({ result });
  } catch (error) {
    self.postMessage({ error: error.message });
  }
};
