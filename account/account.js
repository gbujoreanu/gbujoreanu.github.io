(function () {
  "use strict";
  const client = window.AppAuth?.client;
  const signedOut = document.getElementById("signedOut");
  const signedIn = document.getElementById("signedIn");
  const recovery = document.getElementById("recovery");
  const form = document.getElementById("authForm");
  const email = document.getElementById("email");
  const password = document.getElementById("password");
  const message = document.getElementById("authMessage");
  const submit = document.getElementById("submitAuth");
  const requestedPath = new URLSearchParams(location.search).get("returnTo");
  const returnTo = ["/tracker/", "/golf/", "/"].includes(requestedPath) ? requestedPath : null;
  let mode = "signin";

  if (!client) return showMessage("Account service could not load. Please refresh.", true);

  document.querySelectorAll("[data-mode]").forEach((button) => button.addEventListener("click", () => {
    mode = button.dataset.mode;
    document.querySelectorAll("[data-mode]").forEach((item) => item.classList.toggle("active", item === button));
    submit.textContent = mode === "signin" ? "Sign in" : "Create account";
    password.autocomplete = mode === "signin" ? "current-password" : "new-password";
    showMessage("");
  }));

  form.addEventListener("submit", async (event) => {
    event.preventDefault(); submit.disabled = true; showMessage("Working…");
    const credentials = { email: email.value.trim(), password: password.value };
    const confirmationUrl = `${location.origin}/account/${returnTo ? `?returnTo=${encodeURIComponent(returnTo)}` : ""}`;
    const result = mode === "signin"
      ? await client.auth.signInWithPassword(credentials)
      : await client.auth.signUp({ ...credentials, options: { emailRedirectTo: confirmationUrl } });
    submit.disabled = false;
    if (result.error) return showMessage(result.error.message, true);
    if (mode === "signup" && !result.data.session) showMessage("Check your email to confirm the account. The confirmation link will return you here.");
    if (result.data.session && returnTo) location.replace(returnTo);
  });

  document.getElementById("forgotPassword").addEventListener("click", async () => {
    if (!email.value.trim()) return showMessage("Enter your email address first.", true);
    const { error } = await client.auth.resetPasswordForEmail(email.value.trim(), { redirectTo: `${location.origin}/account/` });
    showMessage(error ? error.message : "Password-reset email sent.", Boolean(error));
  });
  document.getElementById("signOut").addEventListener("click", () => client.auth.signOut());
  document.getElementById("recoveryForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const recoveryMessage = document.getElementById("recoveryMessage");
    recoveryMessage.textContent = "Updating…";
    const { error } = await client.auth.updateUser({ password: document.getElementById("newPassword").value });
    recoveryMessage.textContent = error ? error.message : "Password updated. You can continue to your apps.";
    recoveryMessage.classList.toggle("error", Boolean(error));
    if (!error) setTimeout(() => location.replace(returnTo || "/account/"), 800);
  });

  client.auth.onAuthStateChange((event, session) => renderSession(session, event));
  client.auth.getSession().then(({ data }) => renderSession(data.session));

  function renderSession(session, event = "") {
    const recovering = event === "PASSWORD_RECOVERY";
    recovery.hidden = !recovering;
    signedOut.hidden = Boolean(session) || recovering; signedIn.hidden = !session || recovering;
    if (session) {
      document.getElementById("accountEmail").textContent = session.user.email || "Your account";
      if (returnTo && !recovering) location.replace(returnTo);
    }
  }
  function showMessage(text, error = false) { message.textContent = text; message.classList.toggle("error", error); }
})();
