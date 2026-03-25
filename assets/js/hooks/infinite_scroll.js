export const InfiniteScroll = {
  mounted() {
    this.observer = new IntersectionObserver(
      (entries) => {
        const entry = entries[0];
        if (entry.isIntersecting && this.el.dataset.hasMore === "true") {
          const event = this.el.dataset.event || "load_more";
          // Collect data-param-* attributes as event payload
          const params = {};
          for (const [key, value] of Object.entries(this.el.dataset)) {
            if (key.startsWith("param")) {
              // Convert "paramStatus" -> "status", "paramId" -> "id"
              const paramKey = key.charAt(5).toLowerCase() + key.slice(6);
              params[paramKey] = value;
            }
          }
          this.pushEvent(event, params);
        }
      },
      {
        root: this.el.dataset.scrollRoot
          ? this.el.closest(this.el.dataset.scrollRoot)
          : null,
        rootMargin: "200px",
      }
    );
    this.observer.observe(this.el);
  },

  updated() {
    this.observer.disconnect();
    this.observer.observe(this.el);
  },

  destroyed() {
    this.observer.disconnect();
  },
};
