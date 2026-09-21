// See the Tailwind configuration guide for advanced usage
// https://tailwindcss.com/docs/configuration

let plugin = require("tailwindcss/plugin");

module.exports = {
  content: ["./js/**/*.js", "../lib/*_web.ex", "../lib/*_web/**/*.*ex"],
  theme: {
    extend: {
      fontFamily: {
        sans: [
          "Inter",
          "ui-sans-serif",
          "system-ui",
          "-apple-system",
          "BlinkMacSystemFont",
          "Segoe UI",
          "Roboto",
          "Helvetica Neue",
          "Arial",
          "Noto Sans",
          "sans-serif",
        ],
      },
      colors: {
        'vyaasa': '#FF8B00',
        cream: {
          50: '#FDFAF4',
          100: '#FAF6EE',
          200: '#F4ECDD',
        },
        brand: {
          50: '#FFF6EC',
          100: '#FFE9D2',
          200: '#FFD0A1',
          300: '#FFB36B',
          400: '#FF983A',
          500: '#FF8B00',
          600: '#E67800',
          700: '#B85F00',
        },
        helper: {
          bg: '#FFF1DE',
          border: '#F6D9AE',
        },
      },
      boxShadow: {
        'card-soft': '0 1px 2px rgba(16,24,40,0.04), 0 1px 3px rgba(16,24,40,0.06)',
      },
    },
  },
  plugins: [
    require("@tailwindcss/forms"),
    plugin(({ addVariant }) =>
      addVariant("phx-click-loading", [
        "&.phx-click-loading",
        ".phx-click-loading &",
      ]),
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-submit-loading", [
        "&.phx-submit-loading",
        ".phx-submit-loading &",
      ]),
    ),
    plugin(({ addVariant }) =>
      addVariant("phx-change-loading", [
        "&.phx-change-loading",
        ".phx-change-loading &",
      ]),
    ),
  ],
};
