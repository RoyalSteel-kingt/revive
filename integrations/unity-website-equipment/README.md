# Website equipment bridge — rifle prototype

This patch targets the ReviveAccountClient.cs in your saved Singularity.zip from October 20. It does not replace scenes, movement, networking, or the server build.

## Install

1. Back up Assets/Scripts/ReviveAccountClient.cs in your current Unity project.
2. Compare account-client.patch with your current file. If unchanged since October 20, replace that one script with the included Assets/Scripts/ReviveAccountClient.cs. Keep its existing .meta file. If newer, merge the small diff instead.
3. Let Unity compile, then rebuild your desktop client. No scene component or secret key changes are needed.
4. Equip a Flux Rifle in the website Inventory primary position. In the game, sign in or click Refresh available equipment at the deployment kiosk. The selected rifle should match the equipped UUID. Unequipping on the website then refreshing selects unarmed.
5. Deploy and extract using the existing rifle test mission. Refresh Inventory on the website to see the server-set location and condition. Website mutations are locked while an active mission exists.

## Behavior

Sign-in and inventory refresh read inventory_position alongside the existing owner-scoped records. EquippedItem("primary"), EquippedItem("backup"), EquippedItem("shield") and EquippedItem("bag") expose the saved positions. UseSavedEquipment() selects the equipped, usable Flux Rifle. Home rifles no longer become selected accidentally after refresh. A manual in-game selection remains a temporary override until the next refresh.

Only the current rifle/unarmed prototype deploys and settles. This patch does NOT implement shield damage, backpack capacity, consumable use, full-loadout loss/return, or gameplay encumbrance. Those require a coordinated game/server milestone. It does not reserve all the website backpack contents. Server reservation still verifies the rifle owner and condition; this read patch grants no client write authority.

## Validation

The patch preserves the existing account client's public methods, session store and authentication requests. The website and preparation logic were tested separately. Unity is not installed in the build environment, so this script could not be compiled or play-tested here. Verify in your editor before replacing a working player build. No saved possessions were modified to prepare this patch.
