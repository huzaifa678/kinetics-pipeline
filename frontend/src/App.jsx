import { useState } from "react";
import { useAuth } from "react-oidc-context";
import { API_BASE, HOSTED_UI, oidcConfig } from "./config.js";

// Read a File as a base64 string and return the base64 part after the comma.
function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(String(reader.result).split(",")[1]);
    reader.onerror = reject;
    reader.readAsDataURL(file);
  });
}

export default function App() {
  const auth = useAuth();
  const [file, setFile] = useState(null);
  const [topK, setTopK] = useState(5);
  const [preds, setPreds] = useState(null);
  const [variant, setVariant] = useState(null);
  const [error, setError] = useState("");
  const [busy, setBusy] = useState(false);

  async function predict() {
    if (!file) return;
    setBusy(true);
    setError("");
    setPreds(null);
    try {
      const video_b64 = await fileToBase64(file);
      const res = await fetch(`${API_BASE}/predict`, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${auth.user?.access_token}`,
        },
        body: JSON.stringify({ video_b64, top_k: Number(topK) }),
      });
      if (!res.ok) throw new Error(`${res.status} ${res.statusText}`);
      const data = await res.json();
      setPreds(data.predictions ?? []);
      setVariant(data.model_variant ?? null);
    } catch (e) {
      setError(String(e.message ?? e));
    } finally {
      setBusy(false);
    }
  }

  function logout() {
    auth.removeUser();
    if (HOSTED_UI) {
      const u = encodeURIComponent(oidcConfig.redirect_uri);
      window.location.href = `${HOSTED_UI}/logout?client_id=${oidcConfig.client_id}&logout_uri=${u}`;
    }
  }

  if (auth.isLoading) return <main className="card">Loading…</main>;
  if (auth.error) return <main className="card error">Auth error: {auth.error.message}</main>;

  if (!auth.isAuthenticated) {
    return (
      <main className="card">
        <h1>Kinetics Action Recognition</h1>
        <p>Sign in to classify a short video clip.</p>
        <button onClick={() => auth.signinRedirect()}>Sign in</button>
      </main>
    );
  }

  const max = preds && preds.length ? preds[0].score : 1;

  return (
    <main className="card">
      <header>
        <h1>Kinetics Action Recognition</h1>
        <button className="ghost" onClick={logout}>
          Sign out
        </button>
      </header>

      <label className="field">
        Video clip (.mp4)
        <input type="file" accept="video/mp4,video/*" onChange={(e) => setFile(e.target.files?.[0] ?? null)} />
      </label>

      <label className="field">
        Top-k
        <input type="number" min="1" max="50" value={topK} onChange={(e) => setTopK(e.target.value)} />
      </label>

      <button disabled={!file || busy} onClick={predict}>
        {busy ? "Predicting…" : "Predict"}
      </button>

      {error && <p className="error">{error}</p>}

      {preds && (
        <section className="results">
          <h2>Predictions{variant ? ` · ${variant}` : ""}</h2>
          {preds.length === 0 && <p>No predictions.</p>}
          {preds.map((p) => (
            <div className="bar-row" key={p.label}>
              <span className="bar-label">{p.label}</span>
              <span className="bar-track">
                <span className="bar-fill" style={{ width: `${(p.score / max) * 100}%` }} />
              </span>
              <span className="bar-score">{(p.score * 100).toFixed(1)}%</span>
            </div>
          ))}
        </section>
      )}
    </main>
  );
}
