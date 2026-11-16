## Particle model path correction (2026-11-13, latest)

Render models prepends `models/` internally. Its `sequence 0 model` field MUST
be relative to that directory (e.g. `halo/fx/reach/assault_rifle_0.mdl`). Lua
precache and filesystem dependencies still require the full `models/...` path.
Do not duplicate the prefix or recompile assets to fix this lookup failure.
The converter/schema/package checks now enforce the distinction. All three
installed native PCFs and their ten cached mesh layers are corrected; every
other PCF field and all model files remain unchanged. 29 offline checks pass.
Fresh-session rendering still needs confirmation. Evidence/current protection
checkpoint: .build/particles/gen3/runtime/model_paths. Earlier PCF hashes below
are historical; use this checkpoint for subsequent roster expansions.

## Native particle gameplay test (2026-11-13, latest authorization)

User requested wiring the converted PCFs into NPCs to distinguish particle-editor
ERROR meshes from real gameplay loading failures. 54 native effect names are
connected in campaign_evolved/particles.lua and weapon_fx.lua. Metadata is emitted
by gen3_particle_runtime into particle_data.lua. Precaches model dependencies;
client load results: data/ce8/particle_models.json. No PCF/model/texture rebuilds.
CP0 retains existing muzzle anchors; auxiliary native sockets use AddControlPoint.
No Lua particle simulation/rendering. Original CER/PRP routes remain where native
replacements are absent or their CP contracts conflict. Six held composite impact
CP conflicts are converter defects, not unsupported engine features. See canonical
.build/particles/gen3/runtime/STATUS.txt and installed.json for exact mappings and
character gaps. New gameplay appearance is UNVERIFIED; no CER assets retired.

## Remaining Gen3 particle layers (2026-11-13)

- User accepted the expanded 59-effect roster preview: "They look amazing."
  Recorded build/scope: gen3/pivots/before/baseline.json. The four Hunter roots
  retain their earlier acceptance. Six pivot-sheet corrections affecting five
  public effects follow that acceptance; see gen3/pivots/RESULT.txt.
- Reach mirrors vertex UVs inside its fixed authored sprite rectangle; NEVER
  mirror the padded output card and move its registration offset. Derive the
  rectangle from authored bitmap registration plus particle center offset.
  Frame UV animation must not move that rectangle. gen3_particle_pivots audits
  all current Reach sprite layers against the compiled game geometry.
- User permits a documented native ambient-light approximation for smoke/blood
  with separate diffuse/emissive terms. Preserve source artwork, full-light RGB,
  alpha and clocks; report dim-light error. No missing assets may be invented.
- --preserve rejects accepted graph/texture changes during effect additions.
  gen3/remaining is a HISTORICAL pre-expansion baseline. Do not overwrite it or
  reuse it as current acceptance after the pivot fix. Capture the current build
  for later expansions. --texture-correction gen3/pivots permits only its six
  audited VTFs, keeping every draw graph and other dependency unchanged.
  New whole compositions still require source comparison; acceptance of V5 does
  not validate new effects or production attachment/performance behavior.
- Keep unresolved state inputs, random clocks, mesh materials, physics and
  engine integration explicit. Never present successful siblings as a whole FX.
  Receipts, installed status and remaining gaps are in gen3/roster_preview.

## Scoped Gen3 particle batch (2026-11-13)

- User rejected the v3 control cleanup for missing sprites/wrong colors.
  Never publish fractional-second SHT totals with FPS=1. Use integer ticks and
  matching PCF clocks; Source CSheet truncates its interpolation total to int.
  Retain native radius/rotation and original sheets wherever possible. Validate
  actual compiled sprite appearance/clock, not just unique-control counts.
- 32 whole particle-layer compositions are installed for editor comparison in
  particles/halo_weapons.pcf and halo_creatures.pcf. New visuals are UNVERIFIED;
  gameplay still uses the existing CER packs. No character/weapon assets changed.
- Exact strings: particles/halo_effects.txt. Remaining work and conversion tools
  are in the viewer's canonical .build/particles/gen3/HANDOFF.txt and
  roster_preview/COVERAGE.txt. Do not claim the whole roster is converted.
- Require complete source-layer closure and finite/owner-bound lifetimes before
  publishing roots. Use compact native emitters, not per-sample/birth expansion.
- Current control/pivot revision: 155 weapon, 41 creature and 50 Hunter
  definitions; zero repeated functions per control group. V5 repairs rejected
  v3 visuals; use controls/validation.json and appearance.json for test results.
  This revision needs fresh-session whole-effect comparison before acceptance.

## Compact native particle conversion (2026-11-13)

- User approved compact native equivalents for Hunter distribution/volume
  mappings. Do not create separate systems for sampled random directions or
  profile cards. Preserve real layers, materials, physics and event windows;
  keep lifetime/size/spin tied to their sprite sequence. Record approximations.
- No permission to invent missing assets is implied. Missing-source rules
  still apply. Reusable implementation: gen3_particle_distributions.py.
- Hunter editor preview: 50 definitions, 25 families, four public FX;
  53,002 bytes. Earlier 68,302-byte compact preview was accepted; v3 was rejected.
  The v5 repair needs whole-effect visual comparison; offline evidence is saved.
  Canonical evidence: .build/particles/gen3/hunter_preview/native_summary.json
  and HANDOFF.txt. Production PCFs and runtime bindings are unchanged.

## Particle goal redirected to Reach / Halo 3 / ODST (2026-11-12)

- Convert the effects this addon requires from Reach and Halo 3/ODST to native
  PCFs. Reach is the primary candidate; Halo 3 covers Flood and sandbox gaps.
  ODST is a separate source variant, not assumed identical to Halo 3.
- Scope: .build/particles/GOAL.txt; next work: .build/particles/gen3/HANDOFF.txt
  in the canonical export. CER research/conversion notes remain archived in
  place. Earlier CER active-goal/resume instructions are superseded; do not
  continue Niagara fidelity work or publish its staged candidates.
- Replace the installed CER effect definitions/dependencies with validated
  Gen3 conversions, retaining a rollback outside the shipping addon. Preserve
  live bindings until replacements exist; retire unused resources only after
  a reference audit. Keep shared PRP resources and unrelated assets intact.
- PCF-only visuals and stock shaders remain required. Lua dispatch/attachments/
  control points only; no Lua FX simulation/rendering. Preserve source layers,
  curves, material math and timing; document unresolved mappings. Never invent
  missing assets without the user's specific permission.
- Keep three shared packs and short names; existing CE8 dispatch names can
  remain stable. No character/weapon mesh, UV, animation, atlas or LOD rebuilds.

## Permission required for missing or substitute assets (2026-11-10)

- Before generating content absent from the authored game assets, obtain the
  user's explicit permission for that specific content. This includes invented
  animation poses/frames, replacement meshes, textures, sounds, effects and
  substitute asset data. A general request to port or fix something is not
  authorization to invent its missing parts.
- A failed extraction, decode, export, compile, report or validation check never
  authorizes asset synthesis as a workaround. Preserve the failure, investigate
  the cause, and explain what is missing, why faithful conversion failed, and
  exactly what replacement is proposed before asking permission. Do not hide a
  failure by generating plausible content or changing the checks to pass it.
- Existing explicit approval applies only to its stated scope; it does not grant
  permission for unrelated generated assets. Continue independent diagnostics
  and source-preserving fixes while waiting; hold the proposed generation.
- Faithful decoding and format/unit conversion of existing authored content are
  permitted. These do not authorize new poses, fabricated source values or
  replacement artwork.

## Historical goal: CER Niagara-to-PCF conversion (superseded 2026-11-12)

- The entire addon-required effect set is in scope, INCLUDING Hunter cannon
  and Needler pilot effects. Prior acceptance/preservation rules below are
  historical baselines, not exemptions from accuracy corrections.
- Goal: reproduce as much of CER's actual particle logic as native PCF supports.
  Do not redefine success around the converted subset, file validity, a reduced
  feature list or merely acceptable visuals. Keep the goal active while required
  behavior is unfinished or unverified. Work/evidence: .build/particles/batch/accuracy.
- Inspect every active source layer and dependency: sprites, models, ribbons,
  lights, distortion, decals, material math, schedules, transforms, curves,
  forces/collision and state/variant selection. Establish native capabilities
  before calling a feature unsupported; implement supported mappings.
- PCF-only visuals remain mandatory. Lua may dispatch/attach/stop/precache PCFs
  and supply control points; no Lua rendering/simulation or custom shaders.
- Particle-specific models/materials/textures are authorized dependencies.
  Do not re-export or modify character/weapon meshes, UVs, animations or LODs.
  Use the project's approved StudioMDL-CE for particle model compilation.
- Current muzzle flashes still appear spherical. Correct source composition,
  facing/geometry, masks and blend/intensity math from evidence; never guess a
  brightness reduction or conceal missing layers. File checks do not prove a
  match to CER. Compare source outputs and actual native rendering.
- Keep the three shared PCF packs and short readable asset names. Prefer native
  operators when faithful; avoid unnecessary per-layer animated texture bakes.
  Preserve rollback/version identity and atomic installs. No broad live reload
  of sprite sheets; fresh-session rendering validates changed sheet metadata.

## Particle fidelity correction - installed, visual acceptance pending (2026-11-10)

- Current receipt: .build/particles/batch/fidelity/installed.json and RESULT.txt.
  Three packs contain 89 batch roots / 438 layers. 104 muzzle/impact layers use
  evaluated source profiles; 12 blood layers have source-derived material bakes.
  These counts do NOT mean the entire batch is faithful or complete.
- Material mappings retain actual palette/mask rules, renderer overrides,
  dynamic inputs, emission schedules and full sampled sprite curves. Do not
  replace unresolved source inputs with guessed counts, speeds, RGB midpoints
  or generic fades. 327 unresolved renderer entries include alternatives;
  profile failures overlap that list and are not a separate missing-layer total.
- Corrected effects are installed in both copies; color_review is historical.
  Mesh/ribbon/procedural/view/collision-dependent mappings remain unfinished.
  Native model particles are supported; do not call them unsupported merely
  because this converter has not implemented them. Inspect corrected_effects.csv.
- Preserve accepted Hunter cannon and original Needler pilot resources. Only
  Beam Rifle PCF names and the existing hitscan dispatch were added to Lua;
  NO Lua particle simulation, custom shader or model/UV/animation/LOD changes.
- Source random variation is sampled into three correlated native sequences.
  Use native mksheet + VTex, preserve frame timing/SHT, fit the native 2048-page
  limit by scaling cells when necessary, and deduplicate identical VTF bytes.
- Native PCF builds use private temporary binaries, validate their roundtrip,
  then atomically replace output (staging/canonical files may be hardlinked).
  Match generated vector precision to native DMX's ten decimal places.
- A recovered authored layer failing its material build is a validation failure,
  never a silently omitted success. Keep remaining gaps explicit per source.
- Resource tests passed; appearance still requires a fresh GMod session and CER
  comparison. Never force-reload changed sprite sheets or claim visual parity
  from file/schema checks. Historical pilot/batch installers must not overwrite
  this corrected pack. Fidelity installation is recorded; don't rerun blindly.

## Particle blood / missing-layer correction (2026-11-10)

- Preserve blood liquid gradients separately from mist tint. SpriteCard's stock
  $ramptexture supports the authored flesh curves with tiny shared ramps.
  Read each Texture2D's actual SRGB flag; do not infer linear density from a
  DEA suffix. Balance the density before the ramp, clamp both ramp axes, and
  keep Basic_MV free of the mist tint; Drops uses its post-palette tint.
- M_NeedlerBlood_Myst diffuse RGBA sheets use A for density. The similarly
  named red-channel erosion switch addresses a separate noise map. Only an
  explicitly alpha-only *_A sheet uses R; treating diffuse R as opacity made
  blood mist a solid colored cutout. Keep its authored frame grid.
- Brute's copied system has FleshIndex=1 with a separate red palette: do not
  turn it purple by interpreting that selector as the common Elite palette.
- Resolve previous/current Niagara parameter interpolation as a correlated
  range; losing that correlation silently excluded major splash layers.
- Current refinement adds 40 omitted splash/spark/dust/explosion layers. The
  Fuel Rod core uses the same authored DEA/fire-curve mapping as the accepted
  Hunter. Mesh/light/procedural omissions remain explicit, not called complete.
- Evidence/rollback: .build/particles/batch/blood_review. Validation/refine
  installer preserves gameplay Lua and accepted Hunter resources. Fresh-session
  visual testing remains required after native sprite-sheet changes.

## CER particle batch (2026-11-10, supersedes pilot status below)

- The current batch merges three native packs: ce8_weapons, ce8_shields and
  ce8_creatures. Builders/evidence: mcc_viewer.campaign_particle_batch and
  exports/CampaignEvolved/.build/particles/batch. Do NOT run the old pilot or
  Hunter-only installer over these packs; it would discard the new definitions.
- The four accepted Hunter cannon roots and their material/texture dependencies
  are preserved. Added roots cover roster blood, shields, weapon stages and
  Flood events. A converted root can still be partial: consult build.json for
  missing emitters and BATCH.txt for bindings/limits. Do not claim Niagara parity.
- Gameplay dispatch lives in campaign_evolved/particles.lua and the existing
  event hooks. All new visuals are PCF. No Lua particle simulation, sprite/beam
  drawing, cleanup deadline, projectile/AI changes or model/UV/animation builds.
- Respect native sheet grids and opacity channels. Needler smoke uses 5x5/8x8
  sheets, Hunter electrical web 2x2, Flood spores four random static sequences.
  Use native mksheet + VTex; retain the sheet metadata before image data.
- Shared sheets are deduplicated by actual file bytes; install only referenced
  dependencies. Conversion approximations (birth budgets, scatter, envelopes,
  unsupported mesh/light/procedural layers) stay explicit in the batch receipt.
- Validate with mcc_viewer.particle_batch_validation; install with its install
  command. It archives the previous resources/bindings and verifies both copies.
  Fresh-session GMod appearance remains a separate check. Never force a sheet
  refresh or overwrite accepted effects just because a partial root exists.

## Native renderer / code audit (2026-11-10)

- User requires native Source materials only. No custom CE8 shaders, 8tex
  materials, compiled VCS or GPU parameter/light transports in the addon.
- Nine weapon displays now use UnlitGeneric with CE8Gauge selecting pre-baked
  heat/ammo frames and native texture transforms. Bodies stay VertexLitGeneric;
  accepted sword/shield Refract + UnlitGeneric layers are unchanged.
- Keep bloom emission-only. Its copy/composite now uses stock UnlitGeneric
  pp/copy settings ($linearwrite 0), with private buffers and existing stencil
  isolation; never replace it with whole-scene bloom. No shader binaries needed.
- Manual capture scripts and retired rendering code belong outside shipped Lua.
  Existing recovery archive: .build/catalog/retired_lua.zip (native_renderer/).
  Exact removals and validation: .build/catalog/code_audit.json. Retain active
  gameplay reports, dev-map controls, fountain and PRP collider debugging.
- Build displays with mcc_viewer.campaign_native_gauges. No mesh/UV/model/LOD
  or animation rebuild. Old custom-material installers must not overwrite these
  native assets. Export installation rejects custom shader packages.
- Gauge state frames preserve original resolution: 33 heat states; exact clip
  steps for Needler (25) and Needle Rifle (22). Native rotation/scanlines are
  approximations. 57 offline checks pass; restart GMod and visually check gauge
  heat/ammo, emission-only bloom and energy sorting before claiming acceptance.

# CER particle conversion

- PCF ONLY for particle visuals. No Lua effects, ParticleEmitter simulations,
  scripted sprite/beam/trail drawing or Lua visual fallbacks.
- Lua may load/precache, start/stop/attach native PCFs and supply gameplay
  control points. Damage, projectile flight and other gameplay stay separate.
- Convert only effects required by this addon's existing enemies, items and
  weapons, including their dependencies. Do not port the whole game's VFX.
- Reuse shared systems and textures. Preserve authored CER timing, colors,
  masks and attachment intent where supported. Document native approximations
  and unsupported features; do not implement missing visual behavior in Lua.
- Keep a few shared PCFs (weapons, shields, creatures), not a file per effect.
  Put VTFs in textures/ beneath their effect material folder. The first weapon
  pilot is installed but has no production bindings until its live check passes.
- Validate replacement PCFs and assets before switching working effect calls.
  No unrelated model/material/animation/LOD rebuilds. Keep filenames short.
- Canonical policy, builders and evidence are in the MCCAssetViewer workspace,
  AGENTS.md and exports/CampaignEvolved/.build/particles respectively.

# Particle sprite-sheet workflow (validated Hunter pilot)

- Use GMod mksheet.exe to generate the TGA/SHT pair, then GMod
  bin/win64/vtex.exe with -nopause -nop4 and explicit -game/-outdir.
  The shared implementation is mcc_viewer.particle_sheet in MCCAssetViewer.
- Do not manually append SHT resources to legacy VTF files. Let native VTex
  write the resource directory, preload sheet metadata and image layout.
  Sheet metadata must precede image data; resource types must be sorted.
- Validate the actual image resource and embedded sheet. Record live file
  CRCs and script version. Use a fresh game session when failed resources
  remain cached. Do not infer visual success solely from effect creation.
- This workflow fixed the Hunter cannon preview's missing textures. The user
  confirmed charge, muzzle, flight and impact all display. CER appearance
  matching and production integration remain separate from that confirmation.

- Hunter Niagara fidelity revision: recover emitter/version identity, system
  duration/delay, local/world space, birth curves, lifetime curves and renderer
  visibility/pivots before authoring PCF rules. Do not reuse one generic fade
  for every layer. Source 1 cannot directly consume arbitrary Niagara LUTs:
  the Hunter pilot samples size/opacity/pivots into native timed sequences,
  while PCF owns emission/movement/lifetime. Record curve sampling errors and
  unsupported behavior separately from visual approval. Seven shared textures;
  no Lua FX. See hunter/HUNTER.txt and hunter/audit.json.gz. Preview v4 now
  runs 30 seconds; latest Niagara mapping awaits live visual comparison.

- Do not force mat_reloadmaterial, texture Download or material Recompute in
  particle previews after changing embedded sheet layouts. Particle-sheet
  caching is separate; validate updated PCF/VTF assets in a fresh GMod session.
  Check every animated frame rectangle and byte-compare the embedded SHT with
  mksheet output. Preview v5 removes the forced reload. User confirmed proper animated
  sprites after restarting GMod; clean-session playback is validated.

## Hunter cannon layer expansion (2026-11-10)

- User scope: generic debris and rocks only. Do not add surface-specific sand,
  water, glass or other branches. PCF-only policy remains unchanged.
- Existing ce8_creatures.pcf now contains 60 definitions (55 visible children),
  with electrical arcs, flares, steam, smoke, sparks/embers, plasma, generic
  debris/rocks and native refraction. 25 shared VTFs; no new pack or Lua FX.
- Audit every real renderer reference; Niagara index 0 is NULL, not the last
  package export. Exact emitter version + export index determine identity.
  hunter/layers.json: 39 emitters, 64 renderers; 52 native approximations, five
  surface branches excluded, seven light/post-process components unconverted.
- GPU shader evidence, material parents, density reductions and particle caps
  are retained under hunter/layers. Mesh distortion/rocks currently use cards;
  GMod does support model particles, so do not claim mesh rendering impossible.
- 38 Hunter offline checks and 13 Needler checks pass. Preview v6 runs 36 seconds
  and preserves the full impact tail. Fresh GMod session required after sheet
  changes. Production bindings await visual validation of this expansion.
- Current status/limits/build instructions: hunter/HUNTER.txt. Historical pilot
  counts above are superseded. Do not treat previous pilot playback approval as
  approval of the added layers.

## Hunter refraction / frame correction (2026-11-10)

- Hunter preview v6 loaded every resource; user found impact offsets and purple
  layers. Refract's $basetexture replaces its scene source: NEVER bind the
  distortion normal map there. Use $normalmap only; let Refract sample the scene.
  Dependency/report checks must support normalmap-only materials.
- Impact PCF CP0 +X points outward along the hit normal. Normal-axis velocities,
  fixed offsets and surface cards must use that same frame. Preview v7 traces
  a surface and passes its normal, not camera angles at an airborne point.
- Charge vapor legitimately contracts (1 -> .25 over each .7s particle). The
  central cloud grows quickly then collapses. The flare's separate SYSTEM-age
  brightness ramp was missed: now sampled from CER's two-second update curve,
  0 -> peak near .9 normalized age -> 0, with native sequence playback.
  Do not reverse the vapor curve to fake a growing charge.
- 41 offline checks pass; 13 unchanged Needler checks pass. Preview v7 needs a
  fresh GMod session for changed flare sheets. No Lua FX or production rebinding.
  Evidence: hunter/live/layers_v6*.json and hunter/live/refinement_v7.json.

## Hunter charge / impact lifetime (2026-11-10)

- Entity:StopParticlesNamed is CLIENT ONLY. Never call it serverside or mock it
  as a valid server method in tests. Cannon stop dispatch crosses to the client;
  no StopParticles call on the Hunter that would also stop its muzzle systems.
- Explosion decay belongs in PCF operators. No Lua global cleanup deadline.
  Each child retains its own particle lifetime; record extra Source fade
  approximations and distinguish offline validation from observed playback.

## Hunter native PCF drag (2026-11-10)

- Do not copy Niagara damping coefficients into Source Movement Basic drag.
  Validate finite values in [0,1]; drag=2 caused NaN dust positions, corrupted
  combined render bounds, and made unrelated surviving layers disappear.
- The Hunter impact cutoff is fixed by native drag=.5 on dust; muzzle linger
  and steam had the same invalid 2 value and are corrected too. This is a
  native approximation, not equal damping strength across engines. The failed
  parent bounds/anchor workaround is removed. No Lua lifetime workaround.
- Independent-child capture identified dust; v11 full-impact capture has valid
  bounds throughout and user confirmed normal playback. Preserve individual
  layer lifetimes. Evidence: .build/particles/hunter/live/impact_drag_fixed.json.

## Hunter final cannon PCF audit (2026-11-10)

- Four production cannon roots are live. User confirmed the impact tail now
  fades correctly; preserve the valid-drag correction and independent decay.
- Flight flare/refraction now bursts at time zero, keeps constant alpha through
  finite .5s renewals and preserves spinning-card phase with native PCF
  creation-time remapping. Do not restore the generic repeated fade to black.
- Ribbon width uses 24 sampled authored knots (leading bulge retained).
  Flight vapor reuses raw sequence 0 for authored GPU size/opacity LUTs; the
  other three sequences retain charge/muzzle behavior. Keep four 16-frame
  sequences on the existing native mksheet page; do not duplicate textures.
- Rectangular flare components retain X/Y aspect and parent color/brightness
  factors. Flight ember sizes are authored 1..2cm. No runtime Lua changes.
- One PCF + three existing VTFs changed (+2354 bytes), same 60 definitions,
  same caps and resource count. 43 resource + seven source regression checks
  pass; shared-particle validation passes 12. Impact subtree is unchanged.
- Source per-distance spawn, vapor birth modulation, radial flare term,
  shader flicker, view scaling, vector fields and 3D particle meshes remain
  documented approximations. Do not claim exact Niagara parity.
- Receipt: .build/particles/hunter/final/audit.json. Fresh-session appearance
  validation is pending; use the actual Hunter after restarting GMod, not a
  permanent preview script or forced sprite-sheet reload.
## Unique PCF controls (2026-11-13)

- Published particle systems must not contain repeated function types in their
  initializers, operators, emitters, renderers, forces or constraints. In
  particular, never ship sampled Remap Initial Scalar / Radius Scale chains.
- Use the viewer's shared gen3_particle_controls pass and package uniqueness
  audit. Do not hide repeated controls in additional sampled child systems.
  Preserve genuine authored layers, timing and sprite-lifetime correlations.

