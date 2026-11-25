# Changelog

## LeanTube v0.10.2

### Playback

- Set **Auto maximum resolution** in Settings, from 144p to 2160p (4K), or choose **No limit**. Click the resolution label in the player to change quality for the current video. Quality switches preserve playback position and pause state.
- Read up to 60 seconds ahead, within the packet memory limits, while keeping the three-second startup buffer target.
- Report signed-in watch progress to YouTube every 10 seconds during playback. Reopen an unfinished video 10 seconds before its saved position.
- Show a five-second **Up Next** countdown with **Play now** and **Cancel**. Autoplay follows the next playable video in the current feed.

### Browsing and interface

- Continue loading Home recommendations using the feed’s next-page token. Scroll again to retry a failed page request.
- Preview videos on focused feed cards. **Feed previews** and **Preview audio** can be controlled separately in Settings.
- Wrap full video titles on cards and in the player. Show a **4K** badge when YouTube metadata or stream dimensions establish 4K availability.
- Use Roboto and Noto Sans with Unicode fallback, and use the webOS SDL2 build for Magic Remote D-pad and pointer input.

### SponsorBlock

- Choose which categories to skip automatically from the sidebar. Sponsors are enabled by default. Other options include intros, outros, self-promotion, like and subscribe reminders, previews and recaps, filler, and non-music sections in music videos.
- Show muted category colors on the timeline and keep markers visible after a segment is skipped.

### Install

Add the [LeanTube feed](https://github.com/spcljense/leantube/releases/latest/download/repo.json) in Homebrew Channel or sideload the ARM IPK from the release assets.
