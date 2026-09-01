(function () {
  "use strict";
  const client = window.AppAuth?.client;
  const signedOut = document.getElementById("signedOut");
  const signedIn = document.getElementById("signedIn");
  const form = document.getElementById("authForm");
  const email = document.getElementById("email");
  const password = document.getElementById("password");
  const message = document.getElementById("authMessage");
  const submit = document.getElementById("submitAuth");
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
    const result = mode === "signin"
      ? await client.auth.signInWithPassword(credentials)
      : await client.auth.signUp({ ...credentials, options: { emailRedirectTo: `${location.origin}/account/` } });
    submit.disabled = false;
    if (result.error) return showMessage(result.error.message, true);
    if (mode === "signup" && !result.data.session) showMessage("Account created. Check your email to confirm it, then sign in.");
  });

  document.getElementById("forgotPassword").addEventListener("click", async () => {
    if (!email.value.trim()) return showMessage("Enter your email address first.", true);
    const { error } = await client.auth.resetPasswordForEmail(email.value.trim(), { redirectTo: `${location.origin}/account/` });
    showMessage(error ? error.message : "Password-reset email sent.", Boolean(error));
  });
  document.getElementById("signOut").addEventListener("click", () => client.auth.signOut());

  client.auth.onAuthStateChange((_event, session) => renderSession(session));
  client.auth.getSession().then(({ data }) => renderSession(data.session));

  function renderSession(session) {
    signedOut.hidden = Boolean(session); signedIn.hidden = !session;
    if (session) document.getElementById("accountEmail").textContent = session.user.email || "Your account";
  }
  function showMessage(text, error = false) { message.textContent = text; message.classList.toggle("error", error); }
})();
