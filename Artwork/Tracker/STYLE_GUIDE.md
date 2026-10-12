# Buffeteria tracker head art guide

The tracker uses expressive floating heads with Classic Warcraft race features
and crisp, detailed painterly rendering. Happy, annoyed, and furious expressions
carry the mood. Natural skin, face fur, bone, and eye colors stay stable across
the three portraits, under the same neutral lighting. The original sheets retain
natural hair colors. The sibling `*Colored.png` sheets tint scalp hair muted green
for happy, copper-orange for annoyed, and crimson-red for furious. They are the
default in-game artwork; the **Colored hair** setting restores the originals.
Keep facial hair and eyebrows natural. Tauren mane can carry the color while its
face fur, muzzle, horns, and chin tuft stay natural. No emitted light or skin wash.

## Classic references

Use original character anatomy and race silhouettes as the foundation.
Blizzard's [WoW Classic Primer](https://news.blizzard.com/en-us/article/23090134/wow-classic-primer-for-new-players)
describes the restoration of original character models and includes a
[Classic character creation screenshot](https://bnetcmsus-a.akamaihd.net/cms/content_entry_media/HT4WZ9O6IHD41565217358487.jpg)
with the eight original race portraits and a male orc model.

The [original World of Warcraft manual](http://us.media.blizzard.com/manuals/wow/wow-classic-manual-enUS.pdf)
provides period artwork: printed pages 174-175 show gnomes and an engineer
concept, page 179 shows a night elf and tauren, page 182 shows orc models,
page 183 includes a tauren turnaround, and page 187 shows a troll model.
PDF page numbers are one greater than those printed numbers. These images
guide shape and character; their scene lighting is not part of our sprites.

Blizzard's [Classic first steps guide](https://news.blizzard.com/en-us/article/23317716/taking-your-first-steps-in-world-of-warcraft-classic)
establishes the Darkspear, Forsaken, and original faction context. Later retail
race variants should not replace these identities.

## Race design targets

These are Buffeteria's art decisions based on the references, rather than an
exact reproduction of a selectable in-game face. Hairstyles and small
accessories identify our mascots; they are not requirements for every member
of a race.

| Head | Features to retain and emphasize | Avoid |
| --- | --- | --- |
| Orc | Olive-green skin, heavy brow ridge, broad flat nose, projecting square jaw, lower tusks, pointed ears, dark crest hair. | Yellow-green illumination, oversized baby eyes, a soft round jaw. |
| Gnome | Compact round head, prominent rounded ears, bulbous nose, muted ash-grey hair with matching silver-grey moustache and beard, bronze engineer goggles above the eyes. | Brilliant white hair dominating the face, pointed goblin ears, green skin, a heavy dwarf jaw, luminous lenses. |
| Night Elf | Lavender skin, angular cheekbones, long blade-shaped ears, swept brows, silver eyes, purple markings and violet hair. | A generic human face with pointed ears, eye bloom spilling over the skin. |
| Tauren | Bovine muzzle and nostril pad, heavy brow, brown fur, coarse mane, curved horns with ears beneath them. | A teddy-bear face, human mouth anatomy, antlers or later Highmountain motifs. |
| Human | Strong jaw and brows, blue eyes, chestnut hair and beard, natural warm skin. | Glossy plastic skin, exaggerated round eyes, orange or red mood washes. |
| Troll | Long lean face and hooked nose, blue skin, long lower-jaw tusks, swept pointed ears, purple mohawk. | An orc jaw painted blue, short button nose, later Zandalari motifs. |
| Undead | Gaunt formerly human face, hollow cheeks, dry grey-green skin and exposed bone, damaged nose, sparse hair. | A healthy grey human, a bare clean skull, wet gore or glowing haze. |
| Xaru | Josh "Xaryu" Lujan's lean face, brown eyes, dark expressive brows, exposed widow's-peak hairline with high temples, longer swept-back dark hair falling behind the ears to jaw level with feathered ends, moustache and small goatee; visible painted tonal planes and grouped brushstrokes. | A generic wizard face, photographic skin, heavy full beard, short cropped hair, headband, circlet, hat or any accessory obscuring his hairline. |

Xaryu is a streamer homage available to every class, with the same expressions
and floating-head treatment as the race portraits. Likeness references are his
[public profile portrait](https://x.com/xaryu), including its unobstructed hairline.
The existing Human and Orc sheets supply the painting style, not the facial identity.
His face and hairstyle identify this mage homage; no headwear is needed.

## Expression and rendering

Happy uses lifted relaxed brows, raised cheeks, and a clear smile. Annoyed uses
lowered brows, narrowed eyelids, and a closed downturned mouth. Furious uses
a deeply compressed brow, tense nose, and bared clenched teeth. Keep facial
structure, hair, accessories, tusks, and horns consistent across the set.

Use matte materials, clear facial planes, and controlled neutral highlights.
Do not bake green, amber, or red status light into the face or silhouette.
No colored rim, neon outline, bloom, haze, or face-wide color wash. The night
elf's intrinsic silver eyes can remain bright within their own shape.

The gold cast cue is a separate texture behind the head. Its animation must
not brighten the portrait with an additive copy of the face. Buff icon borders
continue to provide green, orange, and red status colors.

## Production and review

Source PNGs contain three square cells in Happy, Grumpy, Angry order. Each
head ends at its jaw, chin, or beard, with no neck, throat, shoulders, or body.
Leave true transparent margins around all hair, ears, horns, and tusks. A head
must never touch or cross its cell boundary.

`prompts.json` stores the exact built-in ImageGen prompts and references for
the original sheets. `colored-prompts.json` records the colored hair edits, and
`colored-margin-repair.json` records the Troll margin correction.
`python tools/build_tracker_art.py` packs both sets into
uncompressed 256 x 256 RGBA TGAs and rebuilds each external silhouette halo.
Packing preserves the generated artwork's alpha; it does not recolor faces.

Review all three moods at 32, 64, and 128 pixels on light and dark backgrounds.
Check expression readability, identity consistency, clipped features, colored
fringes, and transparent edges. In-game review with `/buffdev preview` must
also confirm that the cast halo leaves the face crisp against actual scenery.
Automated Lua checks cover tracker behavior, not visual authenticity.
