import React, { useEffect, useState } from "react";

function App() {
  const [data, setData] = useState(null);
  const [health, setHealth] = useState(null);

  useEffect(() => {
    fetch("/api/config")
      .then((response) => response.json())
      .then((result) => setData(result));

    fetch("/api/health")
      .then((response) => response.json())
      .then((result) => setHealth(result));
  }, []);

  return (
    <div
      style={{
        maxWidth: "800px",
        margin: "50px auto",
        fontFamily: "Arial"
      }}
    >
      <h1>Kubernetes ConfigMap & Secret Demo</h1>

      <h2>Backend Configuration</h2>

      {data && (
        <div>
          <p>
            <strong>Application:</strong> {data.appName}
          </p>

          <p>
            <strong>Environment:</strong> {data.environment}
          </p>

          <p>
            <strong>Backend Port:</strong> {data.port}
          </p>
        </div>
      )}

      <h2>Backend Health</h2>

      {health && (
        <p>
          <strong>Status:</strong> {health.status}
        </p>
      )}
    </div>
  );
}

export default App;