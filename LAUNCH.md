# Launching Blood Pact on CurseForge

## 1. Test in game (about 30 minutes)

1. Copy the `BloodPact` folder into `World of Warcraft\_forever_\Interface\AddOns\`.
2. Log in, type `/bp whoami`, and copy the GUID it prints.
3. Paste that GUID into `ROOT_ADMINS` in `Core/RBAC.lua` (this makes you ADMIN), then `/reload`.
4. Solo test: `/bp mock on`, open `/bp`, then try `/bp mock boss`, `/bp mock award` and `/bp mock forge`. The forged award must show as provisional and not change standings. Finish with `/bp mock off`.
5. Guild test with two officers online: award DKP from one, confirm the other sees it within a minute. Log one out, award again, log it back in, and confirm it catches up.
6. Fully exit and restart the game, then check that standings are still there. If the WoW Forever saved-data bug is still live, they will refill from guildmates after you log in.

## 2. Publish

1. Sign in at curseforge.com and open the Author Console. Create a project: game World of Warcraft, name "Blood Pact", summary from the TOC Notes line, description from README.md, license MIT.
2. Upload a zip of the `BloodPact` folder (the folder itself inside the zip). Choose the WoW Forever game version and release type "Release" (or "Beta" for a soft launch).
3. CurseForge reviews new projects before they go public.

## 3. Automate later releases (optional)

1. Put this folder in a GitHub repository.
2. The CurseForge project ID (1815593) is already in `BloodPact.toc`.
3. Create an API token in the CurseForge Author Console and save it as the repository secret `CF_API_KEY`.
4. Bump the version in `BloodPact.toc` and `CHANGELOG.md`, then push a tag such as `v0.1.1`. Lint and tests run first; the release uploads only if both pass.
