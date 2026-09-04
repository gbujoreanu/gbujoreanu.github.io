import { loadEcosystemIdentity, renderIdentityAvatar } from "../shared/identity.js?v=3";

(function () {
  "use strict";

  const client = window.AppAuth?.client;
  const $ = (selector) => document.querySelector(selector);
  const signedOut = $("#signedOut");
  const signedIn = $("#signedIn");
  const recovery = $("#recovery");
  const verificationPending = $("#verificationPending");
  const accountState = $("#accountState");
  const form = $("#authForm");
  const email = $("#email");
  const password = $("#password");
  const confirmPassword = $("#confirmPassword");
  const confirmPasswordField = $("#confirmPasswordField");
  const message = $("#authMessage");
  const verificationMessage = $("#verificationMessage");
  const submit = $("#submitAuth");
  const resend = $("#resendConfirmation");
  const profileDialog = $("#profileDialog");
  const requestedPath = new URLSearchParams(location.search).get("returnTo");
  const returnTo = ["/tracker/", "/golf/", "/money/", "/"].includes(requestedPath) ? requestedPath : null;
  const isAuthCallback = new URLSearchParams(location.search).has("code") || location.hash.includes("access_token=");
  const confirmationUrl = `${location.origin}/account/${returnTo ? `?returnTo=${encodeURIComponent(returnTo)}` : ""}`;
  let mode = "signin";
  let pendingEmail = "";
  let cooldownTimer = null;
  let currentUser = null;
  let profile = emptyProfile();
  let profileTrigger = null;
  let pendingAvatarFile = null;
  let removeAvatarRequested = false;
  let avatarPreviewUrl = null;

  if (!client) return showMessage("Account service could not load. Please refresh.", true);

  document.querySelectorAll("[data-mode]").forEach((button) => button.addEventListener("click", () => setMode(button.dataset.mode)));
  form.addEventListener("submit", submitAuthentication);
  resend.addEventListener("click", resendConfirmation);
  $("#changeEmail").addEventListener("click", changeEmail);
  $("#forgotPassword").addEventListener("click", requestSignedOutReset);
  $("#signOut").addEventListener("click", () => client.auth.signOut());
  $("#sendPasswordReset").addEventListener("click", requestSignedInReset);
  $("#recoveryForm").addEventListener("submit", updatePassword);
  $("#editProfile").addEventListener("click", openProfileEditor);
  $("#closeProfile").addEventListener("click", closeProfileEditor);
  $("#cancelProfile").addEventListener("click", closeProfileEditor);
  $("#profileForm").addEventListener("submit", saveProfile);
  $("#handle").addEventListener("input", normalizeHandleInput);
  $("#bio").addEventListener("input", updateBioCount);
  $("#displayName").addEventListener("input", updateEditorAvatar);
  $("#avatarFile").addEventListener("change", selectAvatar);
  $("#removeAvatar").addEventListener("click", removeAvatar);
  $("#discoverable").addEventListener("change", updateDiscoverability);
  profileDialog.addEventListener("close", () => profileTrigger?.focus());
  profileDialog.addEventListener("click", (event) => { if (event.target === profileDialog) closeProfileEditor(); });

  client.auth.onAuthStateChange((event, session) => renderSession(session, event));
  client.auth.getSession().then(({ data }) => renderSession(data.session));

  async function submitAuthentication(event) {
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
  }

  async function resendConfirmation() {
    if (!pendingEmail || resend.disabled) return;
    resend.disabled = true;
    setInlineMessage(verificationMessage, "Sending…");
    const { error } = await client.auth.resend({ type: "signup", email: pendingEmail, options: { emailRedirectTo: confirmationUrl } });
    setInlineMessage(verificationMessage, error ? friendlyAuthError(error) : "Confirmation email sent. Check your inbox and spam folder.", Boolean(error));
    startResendCooldown();
  }

  async function changeEmail() {
    pendingEmail = "";
    stopResendCooldown();
    await client.auth.signOut();
    verificationPending.hidden = true;
    signedOut.hidden = false;
    setMode("signup");
    setAccountState("inactive", "Inactive");
    email.focus();
  }

  async function requestSignedOutReset() {
    if (!email.value.trim()) return showMessage("Enter your email address first.", true);
    const { error } = await client.auth.resetPasswordForEmail(email.value.trim(), { redirectTo: `${location.origin}/account/` });
    showMessage(error ? friendlyAuthError(error) : "If an account is eligible, a password-reset email has been sent.", Boolean(error));
  }

  async function requestSignedInReset() {
    if (!currentUser?.email) return;
    const output = $("#securityMessage");
    setInlineMessage(output, "Sending…");
    const { error } = await client.auth.resetPasswordForEmail(currentUser.email, { redirectTo: `${location.origin}/account/` });
    setInlineMessage(output, error ? friendlyAuthError(error) : "Password-reset email sent. Use the link in that email to continue.", Boolean(error));
  }

  async function updatePassword(event) {
    event.preventDefault();
    const output = $("#recoveryMessage");
    setInlineMessage(output, "Updating…");
    const { error } = await client.auth.updateUser({ password: $("#newPassword").value });
    setInlineMessage(output, error ? friendlyAuthError(error) : "Password updated. You can continue to your apps.", Boolean(error));
    if (!error) setTimeout(() => location.replace(returnTo || "/account/"), 800);
  }

  function setMode(nextMode) {
    mode = nextMode;
    document.querySelectorAll("[data-mode]").forEach((item) => {
      const active = item.dataset.mode === mode;
      item.classList.toggle("active", active);
      item.setAttribute("aria-selected", String(active));
    });
    $("#authTitle").textContent = mode === "signin" ? "Welcome back" : "Create your account";
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
    currentUser = session?.user || null;
    if (session) {
      stopResendCooldown();
      $("#accountEmail").textContent = session.user.email || "Your account";
      $("#securityEmail").textContent = session.user.email || "Your account";
      setAccountState("active", "Active · Email verified");
      loadProfile();
      if (returnTo && isAuthCallback) location.replace(returnTo);
      else honorAccountAnchor();
    } else {
      profile = emptyProfile();
      renderProfile();
      setAccountState("inactive", "Inactive");
    }
  }

  function honorAccountAnchor() {
    if (!['#profileName','#securityTitle'].includes(location.hash)) return;
    requestAnimationFrame(() => document.querySelector(location.hash)?.scrollIntoView({ block:'start' }));
  }

  async function loadProfile() {
    try {
      profile = { ...emptyProfile(), ...(await loadEcosystemIdentity(client, currentUser) || {}), id:currentUser.id };
      renderProfile();
    } catch (error) {
      setInlineMessage($("#privacyMessage"), "Profile details could not load. Please refresh.", true);
    }
  }

  function renderProfile() {
    const name = profile.display_name?.trim() || "Your profile";
    const handleText = profile.handle ? `@${profile.handle}` : "Choose a unique @handle";
    const bioText = profile.bio?.trim() || "Add a short introduction that can become part of your future discoverable profile.";
    $("#profileName").textContent = name;
    $("#profileHandle").textContent = handleText;
    $("#profileBio").textContent = bioText;
    renderIdentityAvatar($("#profileAvatar"), profile, currentUser);
    $("#discoverable").checked = Boolean(profile.discoverable);
  }

  function openProfileEditor(event) {
    profileTrigger = event.currentTarget;
    clearAvatarDraft();
    $("#displayName").value = profile.display_name || "";
    $("#handle").value = profile.handle || "";
    $("#bio").value = profile.bio || "";
    updateBioCount();
    updateEditorAvatar();
    setInlineMessage($("#profileMessage"), "");
    profileDialog.showModal();
    $("#displayName").focus();
  }

  function closeProfileEditor() {
    if (profileDialog.open) profileDialog.close();
    clearAvatarDraft();
  }

  async function saveProfile(event) {
    event.preventDefault();
    const output = $("#profileMessage");
    const displayName = $("#displayName").value.trim();
    const handle = normalizeHandle($("#handle").value);
    const bio = $("#bio").value.trim();
    if (!displayName || displayName.length > 60) return setInlineMessage(output, "Enter a display name between 1 and 60 characters.", true);
    if (!/^[a-z][a-z0-9_]{2,23}$/.test(handle)) return setInlineMessage(output, "Handle must be 3–24 characters, start with a letter, and use only lowercase letters, numbers, or underscores.", true);
    const save = $("#saveProfile");
    save.disabled = true;
    setInlineMessage(output, "Saving…");
    let uploadedPath = null;
    try {
      if (pendingAvatarFile) {
        const extension = ({ "image/jpeg":"jpg", "image/png":"png", "image/webp":"webp" })[pendingAvatarFile.type];
        uploadedPath = `${currentUser.id}/${crypto.randomUUID()}.${extension}`;
        const upload = await client.storage.from("avatars").upload(uploadedPath, pendingAvatarFile, { contentType:pendingAvatarFile.type, cacheControl:"3600", upsert:false });
        if (upload.error) throw upload.error;
      }
      const nextAvatarPath = uploadedPath || (removeAvatarRequested ? null : profile.avatar_path || null);
      const { error } = await client.from("profiles").upsert({ id: currentUser.id, display_name: displayName, handle, bio: bio || null, discoverable: Boolean(profile.discoverable), avatar_path:nextAvatarPath }, { onConflict: "id" });
      if (error) throw error;
      const oldAvatarPath = profile.avatar_path;
      profile = { ...emptyProfile(), ...(await loadEcosystemIdentity(client, currentUser) || {}), id:currentUser.id };
      if (oldAvatarPath && oldAvatarPath !== profile.avatar_path) await client.storage.from("avatars").remove([oldAvatarPath]);
      renderProfile();
      closeProfileEditor();
    } catch (error) {
      if (uploadedPath) await client.storage.from("avatars").remove([uploadedPath]);
      setInlineMessage(output, avatarProfileError(error), true);
    } finally { save.disabled = false; }
  }

  async function updateDiscoverability(event) {
    const checked = event.currentTarget.checked;
    const output = $("#privacyMessage");
    event.currentTarget.disabled = true;
    setInlineMessage(output, "Saving…");
    const { error } = await client.from("profiles").upsert({ id: currentUser.id, discoverable: checked }, { onConflict: "id" });
    event.currentTarget.disabled = false;
    if (error) {
      event.currentTarget.checked = !checked;
      return setInlineMessage(output, profileError(error), true);
    }
    profile.id = currentUser.id;
    profile.discoverable = checked;
    setInlineMessage(output, checked ? "Discoverability is on. No profile search exists yet." : "Discoverability is off.");
  }

  function normalizeHandleInput(event) {
    const normalized = normalizeHandle(event.currentTarget.value).replace(/[^a-z0-9_]/g, "");
    if (event.currentTarget.value !== normalized) event.currentTarget.value = normalized;
  }

  function normalizeHandle(value) {
    return String(value || "").trim().toLowerCase().replace(/\s+/g, "_");
  }

  function updateBioCount() { $("#bioCount").textContent = String($("#bio").value.length); }
  function selectAvatar(event) {
    const file = event.currentTarget.files?.[0] || null;
    if (!file) return;
    if (!["image/jpeg","image/png","image/webp"].includes(file.type)) {
      event.currentTarget.value = "";
      return setInlineMessage($("#profileMessage"), "Choose a JPG, PNG, or WebP image.", true);
    }
    if (file.size > 5 * 1024 * 1024) {
      event.currentTarget.value = "";
      return setInlineMessage($("#profileMessage"), "Choose an image smaller than 5 MB.", true);
    }
    if (avatarPreviewUrl) URL.revokeObjectURL(avatarPreviewUrl);
    pendingAvatarFile = file;
    removeAvatarRequested = false;
    avatarPreviewUrl = URL.createObjectURL(file);
    setInlineMessage($("#profileMessage"), "Image ready. Save your profile to upload it.");
    updateEditorAvatar();
  }

  function removeAvatar() {
    if (avatarPreviewUrl) URL.revokeObjectURL(avatarPreviewUrl);
    avatarPreviewUrl = null;
    pendingAvatarFile = null;
    removeAvatarRequested = true;
    $("#avatarFile").value = "";
    setInlineMessage($("#profileMessage"), "Profile picture will be removed when you save.");
    updateEditorAvatar();
  }

  function clearAvatarDraft() {
    if (avatarPreviewUrl) URL.revokeObjectURL(avatarPreviewUrl);
    avatarPreviewUrl = null;
    pendingAvatarFile = null;
    removeAvatarRequested = false;
    if ($("#avatarFile")) $("#avatarFile").value = "";
  }

  function updateEditorAvatar() {
    const previewIdentity = avatarPreviewUrl
      ? { display_name:$("#displayName").value, handle:$("#handle").value, signedAvatarUrl:avatarPreviewUrl }
      : removeAvatarRequested
        ? { display_name:$("#displayName").value, handle:$("#handle").value, signedAvatarUrl:null }
        : { ...profile, display_name:$("#displayName").value || profile.display_name, handle:$("#handle").value || profile.handle };
    renderIdentityAvatar($("#editAvatar"), previewIdentity, currentUser);
    $("#removeAvatar").hidden = !profile.avatar_path && !pendingAvatarFile;
  }

  function emptyProfile() { return { id:null, display_name:"", handle:"", avatar_url:null, avatar_path:null, signedAvatarUrl:null, bio:"", discoverable:false }; }
  function setAccountState(state, text) {
    accountState.className = `account-state ${state}`;
    accountState.querySelector("strong").textContent = text;
  }
  function profileError(error) {
    const raw = String(error?.message || "Profile could not be saved.");
    if (error?.code === "23505" || /profiles_handle_lower_key|duplicate key/i.test(raw)) return "That handle is already taken. Try another one.";
    if (error?.code === "23514" || /profiles_handle_format/i.test(raw)) return "That handle does not meet the required format.";
    return "Profile could not be saved. Please review your details and try again.";
  }
  function avatarProfileError(error) {
    const raw = String(error?.message || "");
    if (/bucket|avatar_path|schema cache|column/i.test(raw)) return "Profile pictures are not ready yet because the secure avatar migration has not been applied.";
    if (/mime|content type|file size|payload/i.test(raw)) return "That image type or size is not allowed. Use a JPG, PNG, or WebP under 5 MB.";
    return profileError(error);
  }
  function friendlyAuthError(error) {
    const raw = String(error?.message || "Something went wrong. Please try again.");
    if (/rate limit|too many requests|email rate/i.test(raw)) return "Email limit reached for now. Please wait a few minutes before trying again.";
    return raw;
  }
  function showMessage(text, error = false) { setInlineMessage(message, text, error); }
  function setInlineMessage(element, text, error = false) {
    element.textContent = text;
    element.classList.toggle("error", error);
  }
})();
