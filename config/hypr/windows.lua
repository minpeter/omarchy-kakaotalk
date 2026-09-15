-- Personal window rules.

-- Wine can expose its empty desktop shell as a tiny XWayland window.
-- Soda reports that shell as steam_proton instead of explorer.exe.
o.window({
  class = "^(explorer\\.exe|steam_proton)$",
  title = "^$",
  xwayland = true,
  float = true,
}, {
  tag = "-default-opacity",
  opacity = "0 0",
  border_size = 0,
  no_shadow = true,
  no_focus = true,
})

-- KakaoTalk maps a short-lived XWayland helper while opening attachments.
-- Keep focus on the chat so closing the helper does not dismiss the scratchpad.
o.window({
  class = "^kakaotalkui\\.exe$",
  title = "^KakaoTalkUI$",
  xwayland = true,
}, {
  no_initial_focus = true,
})
