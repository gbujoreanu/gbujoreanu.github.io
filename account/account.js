(function () {
  "use strict";
  const client = window.AppAuth?.client;
  const signedOut = document.getElementById("signedOut");
  const signedIn = document.getElementById("signedIn");
  const recovery = document.getElementById("recovery");
  const verificationPending = document.getElementById("verificationPending");
  const accountState = document.getElementById("accountState");
  const form = document.getElementById("authForm");
  const email = document.getElementById("email");
  const password = document.getElementById("password");
  const confirmPassword = document.getElementById("confirmPassword");
  const confirmPasswordField = document.getElementById("confirmPasswordField");
  const message = document.getElementById("authMessage");
  const verificationMessage = document.getElementById("verificationMessage");
  const submit = document.getElementById("submitAuth");
  const resend = document.getElementById("resendConfirmation");
  const requestedPath = new URLSearchParams(location.search).get("returnTo");
  const returnTo = ["/tracker/", "/golf/", "/money/", "/"].includes(requestedPath) ? requestedPath : null;
  const confirmationUrl = `${location.origin}/account/${returnTo ? `?returnTo=${encodeURIComponent(returnTo)}` : ""}`;
  let mode = "signin";
  let pendingEmail = "";
  let cooldownTimer = null;

  if (!client) return showMessage("Account service could not load. Please refresh.", true);

  document.querySelectorAll("[data-mode]").forEach((button) => button.addEventListener("click", () => setMode(button.dataset.mode)));

  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    showMessage("");
    confirmPassword.removeAttribute("aria-invalid");
    if (mode === "signup" && password.value !== confirmPassword.value) {
      confirmPassword.setAttribute("aria-invalid", "true");
      confirmPassword.focus();
      return showMessage("The passwords do not match. Please re-enter them.", true);
    }
    submit.disabled = true;
    showMessage("Working…");
    const credentials = { email: email.value.trim(), password: password.value };
    const result = mode === "signin"
      ? await client.auth.signInWithPassword(credentials)
      : await client.auth.signUp({ ...credentials, options: { emailRedirectTo: confirmationUrl } });
    submit.disabled = false;
    if (result.error) return showMessage(friendlyAuthError(result.error), true);
    if (mode === "signup" && !result.data.session) {
      pendingEmail = credentials.email;
      showVerificationPending();
      return;
    }
    if (result.data.session && returnTo) location.replace(returnTo);
  });

  resend.addEventListener("click", async () => {
    if (!pendingEmail || resend.disabled) return;
    resend.disabled = true;
    verificationMessage.textContent = "Sending…";
    verificationMessage.classList.remove("error");
    const { error } = await client.auth.resend({ type: "signup", email: pendingEmail, options: { emailRedirectTo: confirmationUrl } });
    verificationMessage.textContent = error ? friendlyAuthError(error) : "Confirmation email sent. Check your inbox and spam folder.";
    verificationMessage.classList.toggle("error", Boolean(error));
    startResendCooldown();
  });

  document.getElementById("changeEmail").addEventListener("click", async () => {
    pendingEmail = "";
    stopResendCooldown();
    await client.auth.signOut();
    verificationPending.hidden = true;
    signedOut.hidden = false;
    setMode("signup");
    setAccountState("inactive", "Inactive");
    email.focus();
  });

  document.getElementById("forgotPassword").addEventListener("click", async () => {
    if (!email.value.trim()) return showMessage("Enter your email address first.", true);
    const { error } = await client.auth.resetPasswordForEmail(email.value.trim(), { redirectTo: `${location.origin}/account/` });
    showMessage(error ? friendlyAuthError(error) : "If an account is eligible, a password-reset email has been sent.", Boolean(error));
  });
  document.getElementById("signOut").addEventListener("click", () => client.auth.signOut());
  document.getElementById("recoveryForm").addEventListener("submit", async (event) => {
    event.preventDefault();
    const recoveryMessage = document.getElementById("recoveryMessage");
    recoveryMessage.textContent = "Updating…";
    const { error } = await client.auth.updateUser({ password: document.getElementById("newPassword").value });
    recoveryMessage.textContent = error ? friendlyAuthError(error) : "Password updated. You can continue to your apps.";
    recoveryMessage.classList.toggle("error", Boolean(error));
    if (!error) setTimeout(() => location.replace(returnTo || "/account/"), 800);
  });

  client.auth.onAuthStateChange((event, session) => renderSession(session, event));
  client.auth.getSession().then(({ data }) => renderSession(data.session));

  function setMode(nextMode) {
    mode = nextMode;
    document.querySelectorAll("[data-mode]").forEach((item) => item.classList.toggle("active", item.dataset.mode === mode));
    submit.textContent = mode === "signin" ? "Sign in" : "Create account";
    password.autocomplete = mode === "signin" ? "current-password" : "new-password";
    confirmPasswordField.hidden = mode !== "signup";
    confirmPassword.disabled = mode !== "signup";
    confirmPassword.required = mode === "signup";
    confirmPassword.value = "";
    showMessage("");
  }

  function showVerificationPending() {
    signedOut.hidden = true;
    signedIn.hidden = true;
    recovery.hidden = true;
    verificationPending.hidden = false;
    setAccountState("pending", "Verification pending");
    startResendCooldown();
  }

  function startResendCooldown(seconds = 60) {
    stopResendCooldown();
    let remaining = seconds;
    resend.disabled = true;
    resend.textContent = `Resend available in ${remaining}s`;
    cooldownTimer = setInterval(() => {
      remaining -= 1;
      if (remaining <= 0) {
        stopResendCooldown();
        resend.disabled = false;
        resend.textContent = "Resend confirmation email";
      } else resend.textContent = `Resend available in ${remaining}s`;
    }, 1000);
  }

  function stopResendCooldown() {
    if (cooldownTimer) clearInterval(cooldownTimer);
    cooldownTimer = null;
  }

  function renderSession(session, event = "") {
    const recovering = event === "PASSWORD_RECOVERY";
    if (recovering) {
      signedOut.hidden = true;
      signedIn.hidden = true;
      verificationPending.hidden = true;
      recovery.hidden = false;
      return setAccountState("active", "Active · Email verified");
    }
    if (session && !session.user.email_confirmed_at) {
      pendingEmail = session.user.email || "";
      return showVerificationPending();
    }
    recovery.hidden = true;
    verificationPending.hidden = true;
    signedOut.hidden = Boolean(session);
    signedIn.hidden = !session;
    if (session) {
      stopResendCooldown();
      document.getElementById("accountEmail").textContent = session.user.email || "Your account";
      setAccountState("active", "Active · Email verified");
      if (returnTo && event === "SIGNED_IN") location.replace(returnTo);
    } else setAccountState("inactive", "Inactive");
  }

  function setAccountState(state, text) {
    accountState.className = `account-state ${state}`;
    accountState.querySelector("strong").textContent = text;
  }

  function friendlyAuthError(error) {
    const raw = String(error?.message || "Something went wrong. Please try again.");
    if (/rate limit|too many requests|email rate/i.test(raw)) return "Email limit reached for now. Please wait a few minutes before trying again.";
    return raw;
  }

  function showMessage(text, error = false) {
    message.textContent = text;
    message.classList.toggle("error", error);
  }
})();
