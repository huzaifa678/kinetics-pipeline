import React from "react";
import ReactDOM from "react-dom/client";
import { AuthProvider } from "react-oidc-context";
import { oidcConfig } from "./config.js";
import App from "./App.jsx";
import "./styles.css";

// Strip the ?code=…&state=… off the URL after the OIDC redirect completes.
const onSigninCallback = () => {
  window.history.replaceState({}, document.title, window.location.pathname);
};

ReactDOM.createRoot(document.getElementById("root")).render(
  <React.StrictMode>
    <AuthProvider {...oidcConfig} onSigninCallback={onSigninCallback}>
      <App />
    </AuthProvider>
  </React.StrictMode>
);
