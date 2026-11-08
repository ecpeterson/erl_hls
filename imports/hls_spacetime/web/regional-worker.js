import { loadRegionalData } from "./regional-data.js";

/** Parse one optional saved resource derivative off the UI thread. */
self.onmessage = async ({ data }) => {
  try {
    const result = await loadRegionalData({
      ...data,
      progress: (progress) => self.postMessage({ progress }),
    });
    self.postMessage({ result });
  } catch (error) {
    self.postMessage({ error: error.message });
  }
};
