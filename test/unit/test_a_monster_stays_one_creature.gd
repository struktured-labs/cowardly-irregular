extends GutTest

## Sprite audit 2026-11-11 (cowir-sprites 23682 S4, cowir-main ruling 23683). 70 legacy AI sheets (17 early-game ones in
## tip 1, 53 from the later worlds in tip 2) hold a different creature in almost every frame: the unassuming dog attacked
## as a husky, was hit as a bulldog and died as a corgi. Each frame is a legal 256 px frame, so nothing failed. Until those
## sheets are redrawn, a sheet on this REVIEWED list plays its idle picture for attack, hit and dead (manifest only; the
## engine's lunge, knockback and death fade carry the motion), and this guard keeps every frame it shows on that one
## creature. The list is by eye, not by tier: a sheet whose other frames ARE the same creature stays off it, and so does
## the ghost, whose wisp death is the design. Re-review an entry when its art is redrawn.
## 2026-11-18: 17 of the 70 were redrawn from their own idle (paid S4 motion regen, installed at $0) and moved to
## REDRAWN_BY_MOTION_REGEN, where every range ships only on an eye pin plus a colour floor against the idle.

## A live frame must overlap one of its sheet's idle frames by at least this much (the idle guard's own floor).
const MIN_OVERLAP := 0.70
## MOTION frames below that floor ship on EYE + COLOUR (struktured via cowir-main 25446, 2026-11-14): a real lunge overlaps
## its idle 45-55%. Idle and dead keep the overlap floor. COLOUR: the frame's colours match an idle frame's (3-bit-per-channel
## histogram intersection); measured 2026-11-14, the Rat King's own lunge scores 0.79-0.81 and the closest other listed species
## 0.717 against his idle. EYE: a lane looked at THOSE pixels, pinned by hash, so any pixel change needs a fresh look. Colour
## alone cannot refuse a swap here: his unused frames are other rat kings in his palette (frame 4 scores 0.827).
const OVERLAP_ONLY_ANIMS := ["idle", "dead"]
const COLOUR_BITS := 3
const COLOUR_FLOOR := 0.75
## "sheet/anim" -> sha256 of the range's RGBA (transparent pixels zeroed: the import's fix_alpha_border rewrites their RGB).
const EYE_REVIEWED := {
	## cowir-sprites 2026-11-14: sceptre wind-up, then an open-mouthed lunge; his crown, cape, sceptre and grey fur, facing the idle's way.
	"cave_rat_king/royal_spite": "ba78a6bb309b37d0ce43e4fbc5fdc8b9c48872b383f2521ce7578c093fc6eb8a",
	## cowir-sprites 2026-11-18: the 17 REDRAWN sheets below, every range looked at; pinned on the PNG bytes (frame 0 is the shipped soft idle).
	"troll/idle": "cad0fd4d8b7afbe5169ada459c9c62210532367bfce31b486ac20cfb5ece8cdb",
	"troll/attack": "2acd9e79198fdc3a1169a46b02b3963dc51c1f66a8be5dab3708fa154762bce4",
	"troll/hit": "4f025fcfe921aefdafb2f3b43b1d297ec175ba7ade6eeb3d4f8a72ed0e699c3f",
	"troll/dead": "856bcf7760d5f229be2b88c289bab102ba0e5548d5470c94c44bd0fca16ae3ea",
	"unassuming_dog/idle": "5889a4cf692b754354b7b84d0cf168d0ab65da49a17c71cf2b25efc52fdd2818",
	"unassuming_dog/attack": "28eb64bb77e60c597f26e647e610b5ab86f78bc65f3c953b53d1bb1f4c6661c7",
	"unassuming_dog/hit": "9d7ef81e3ac1fb18be766dd640da800da011cb23cb2a865c3741909fbab90a73",
	"unassuming_dog/dead": "0f90497fa2f0d13be7cdecddafc6bfa7e50b034381485fe3cc18f63f14f89877",
	"cave_rat_king/idle": "542f69dacbe9056c8fb3bf2c607f9709e03aa98ea80df600975b175168a7d013",
	"cave_rat_king/attack": "f56203f55e9e051d72ce63fd98f4f00079602d5d9a2062e0ee08ed5f175b4526",
	"cave_rat_king/hit": "e6687fb4fbd5675cd988865390a6ffd81a272592bc43f0a51986fbf6a327c105",
	"cave_rat_king/dead": "500525edb457b5246a21e61a1516706c8fc99fc3cf449c99fdf51767e32828e7",
	"snake/idle": "afd9df8a49144dbc4574bfd8f63d23016ba23e362fbcdfa0a08fbe0253464b98",
	"snake/attack": "5a91ac4e8c00723915d019a17c58ef499f24d2c4c696229439645b23798d94ca",
	"snake/hit": "02dd9e30c1a5f1e013d9912bbd16053a34b7cf46f19c177285691413556d88b4",
	"snake/dead": "4f8e7cb4f2027f0c913403c8b997ef56dab9f7b53d0206d2a4da3a248595ddc8",
	"viper/idle": "15b2463a814427f6e0889ee487c3acb0721b0e033992dbbbeeb7843f17f94a1f",
	"viper/attack": "2231c0e1a0bb4218fe97925e055504854e5340dbb15db65fa3210e6ac9e98d21",
	"viper/hit": "cb0c68d5a2c83db817dcec84000dd12ead7f6f2b49dd349aefd0016c6954571d",
	"viper/dead": "7deaca9c39642b9ad6c4d30198a92e6776133f3509fe701fad0f66c2e9d508b8",
	"toxic_sludge/idle": "8436b44c564a75ac3f60858ce0612f9606ec3d8936906d4b0f1006bf73c312d6",
	"toxic_sludge/attack": "fcb0cf1f6ea3fbd1d0863e67168eed2c1caae4c1ad7c71bb8d525f776b6d1411",
	"toxic_sludge/hit": "69c6bee75fc1b555878c233fe2e7eeac75d0aceb81f531bfdf00f7ef5733de9e",
	"toxic_sludge/dead": "a69f1cae97f54bd472f2bd61d29814603974bbceaeaa9fa40cd9b2342bc614ad",
	"cranky_lady/idle": "c13800cee4f2af5b463aedb408dc3cbcf2ae13d5e90af56915421fa9c327a955",
	"cranky_lady/attack": "e9c9dd8cbbd9cd66d72ee0ba63c8bd3ba18059d7bb804e9f05036e669fbfbe16",
	"cranky_lady/hit": "700679aaf7b89232f21cbe9c37888d9c46ca2dc1e13924d1502a74323c06ffa0",
	"cranky_lady/dead": "634dda440c2e281215ae14948fd5fa8750f9ed4094b95adce58876a262b6778b",
	"skate_punk/idle": "f6af265466976f3bff2866aa95f3eb7d75c98fd5422148bae82a8372953c79c8",
	"skate_punk/attack": "d8dccfa2ea6feb75fee3b3be49b7d66a6a4c16d313d7a48f8b7c8fb9f0c565bb",
	"skate_punk/hit": "1c079bf857c09712c87e67092c7b081aa81f013a03dcd17b38ef48868bc74d11",
	"skate_punk/dead": "2057d50c01575497e40d79275e5d71abc52c823c745bfda49bf4a4e2eaa70def",
	"new_age_retro_hippie/idle": "9e9e24383bfa96707360e4d32c36ed1fca9705c4f3171259aa131685b217e877",
	"new_age_retro_hippie/attack": "5053b129cb8ef852295e687f58c7790d99fce9a3f5d382db0f54252872784743",
	"new_age_retro_hippie/hit": "c891807ee7305b46cf3a5560b0a4d5ab9e85fe803583b7fd3f415e8af5c671d6",
	"new_age_retro_hippie/dead": "b40adb2aa898993236d7749b1e08892f483cfcc07221c1fd3449bff36817a55c",
	"treasure_mimic/idle": "b8a0b4261f05bd8eea32b5f5a4ece400e03895259be97628a2fbf4f2ce436960",
	"treasure_mimic/attack": "5425448ac6f5d72bc4e95ccda27d77791e2e5ffec21977fb8f2ff0dc2c76526d",
	"treasure_mimic/hit": "a4c482e245b806a7647b0e7544540536365e27a21a93a2b95dd88374b69a5ae0",
	"treasure_mimic/dead": "de80027a8c8f5bbc53435a1c88d688cbf20043dbd06296e21bd247200edef9ea",
	"fungoid/idle": "e730226e617e428e1a077a603d1246cbfb16ae14482d2b0978c1e8bfc2342997",
	"fungoid/attack": "81f1ebe440e5e67156f245abdb12c47f51eb15c8acae1c4ba91fd23d66c6e2d5",
	"fungoid/hit": "3572e1a381426c3099e584623c70c519d803bc486fe0fa6e6ba074f8dad5caf4",
	"fungoid/dead": "2d244f96e93564017e7b233dedacd9a4901bb624ba4b270705eabca10d2675e7",
	"diseased_rat/idle": "22b4339de26f5562bffcdbeaedacee3bd4720790b84e02fd3ba502ec5ac78192",
	"diseased_rat/attack": "2ba45e153d11bceef803484d8ea3c6573920aa64d504c08229b133938d93b773",
	"diseased_rat/hit": "e19757da6039488af10babbdfa52c4afd3c667641eaa14b2372adc2fad9f9efd",
	"diseased_rat/dead": "50565f16e72b8736e164a0d09b8b55a8ac0211b8b7eb68a4660c7a0107354e50",
	"elder_mushroom/idle": "ac12bfde68f8e0f0969d6ae4120473f94d660de734fb569deba2dc129bc0a7f8",
	"elder_mushroom/attack": "51d8f1df72586c7aed110f30a7649c2686e2d9d674b48c5b8cfcfa925f2f925d",
	"elder_mushroom/hit": "c23acfc74eb4ca666461d42d8641ca43f45414ae13b6ce866a60360b2cb28d13",
	"elder_mushroom/dead": "3a477045a03567da332415ad1de1eefc03c750420f3558720064d8845e4d7470",
	"giant_bat/idle": "7df079d95d63464a221c730bc0928c70435eb51464198edbff62e54cf7c9b1e0",
	"giant_bat/attack": "7ee312133bfd1249f15fd74ced43902beb0542b2cb222ac77f60c2507d060317",
	"giant_bat/hit": "017dbaef8d917112a73afafb3d481cee3ed8c34702da2c60c4ba63a40b256dbd",
	"giant_bat/dead": "71a3a98cf10f426a27145e39021d04619544e97de5749186f9c9c5f1ed4746c0",
	"blood_wolf_alpha/idle": "1dcc076a1d577a25aa271bd5e1113fd937639ce00d73b9388146b2f9aab5548c",
	"blood_wolf_alpha/attack": "8f12f5953c19bb77b7b9304340fe3f30d950f690f047d01ea57693558b8f160a",
	"blood_wolf_alpha/hit": "9ea9cb27ce142ebf5d12d5defffae3a2cc9910ba10a74361b4e48af6ccc44119",
	"blood_wolf_alpha/dead": "467b0b8ffe358f313cb9f455c26fcef811f20ecc1a913fcf8c4eff2e48f57f14",
	"steam_rat/idle": "0718a8b046a162457925dc676dc564e1501213dd62e4afd6c6fec602d41bfed4",
	"steam_rat/attack": "ce7fdb8e6936263dbc47d991b8619e7739e282ff3f5992992b3d40147d3d60bf",
	"steam_rat/hit": "60d296b422ee82727d912805eac79ea5e9240e935618d481d3e40381c52cebd4",
	"steam_rat/dead": "1547861afc571d3889c4b9fb9a49343e6f2ded7d6c323356f0c0d0a16fe970ac",
	"conveyor_gremlin/idle": "dd99ea87887094adb6ce45bc07ffda558d3670f8c9c71bca2d46f0c4cededd4e",
	"conveyor_gremlin/attack": "bcb2be3f69bcd7cffa02d7a99f25d811515d898e8c867ef4d9f7b819df843ef4",
	"conveyor_gremlin/hit": "a72ab73ce9144f0687ebc3a77a00e3506a6562fa59563dfe420918007a737cd1",
	"conveyor_gremlin/dead": "b545040fd4b99f20fc8958cf133cacd9b4b5b34f9ce9801b050010f408d9ea13",
	## cowir-sprites 2026-11-19: 7 W3 machine sheets redrawn the same way, every range looked at; ironback_beetle and pipe_phantom idle moved to frame 0.
	"brass_golem/idle": "d717d92ba65fea0b4e7770341e141ca4973cdd74c80e7978f15f432e663c68eb",
	"brass_golem/attack": "d254180723ccb9de60ae19887c4013d29d4f277aede8807b0333307a1d9f206c",
	"brass_golem/hit": "7c9c09bc4a1e2d337fa849b55d460f342df98bfda36b13173e8b7373272d5f59",
	"brass_golem/dead": "1935de5f1b1f6c90200f84cbc3a9f9c8146ecdea19eab81183b884af54d46113",
	"clockwork_sentinel/idle": "643da15afb6bfed6eacaef821a08169375a96ec70b5186e54d6b54fea83b77f3",
	"clockwork_sentinel/attack": "dc16560a4ac5459cb65b648a18e47cdb91907c29a2e0f35eae4768816fece6a9",
	"clockwork_sentinel/hit": "0fc8ecae5d960ffa6047125f09c9fd7cd99a3ac6c3a603883395b1fdbd4ddc5b",
	"clockwork_sentinel/dead": "246116381ae17dd7de4b84f4dd3cafa5f20f55caeb4810f63a20288f0a5ca273",
	"assembly_line_automaton/idle": "feefeec85dc8b3ca13da17452140a8ab99b8b9b68fad7d7c20d868175b831cc0",
	"assembly_line_automaton/attack": "52dd7edd5f0576a8c1b3f099230e101624975747bb496b3488dd94599d78ccef",
	"assembly_line_automaton/hit": "abac2e0687e471edbd383fa000a4c0b3ee2a79db193acdbfe1ae9341242d8b7a",
	"assembly_line_automaton/dead": "d78f1f9ac875a36316e5bcb9207f64556e255f8eac346237d0a426a5a5d75094",
	"ironback_beetle/idle": "83328d3cb78b45e44327bf2fad36334fea49239f666f31c82e4a6727fbc09b28",
	"ironback_beetle/attack": "ca4efaf52210b3931361fe6102c4dee86490975edea3ff00a65529d5465e32b4",
	"ironback_beetle/hit": "43d90fa4ec5d859483501bb40172919603e5124266b231096770ff6d692b3b6e",
	"ironback_beetle/dead": "602a3e45f247a503f988beffcab7ea16dcd057ce7fd482a05116c066384d3236",
	"rust_elemental/idle": "1192af5bb712d444c8e7fee16ab4a1484ae3701d99871ef3a666e59f1bb905e4",
	"rust_elemental/attack": "3821a3b71de1189ab086350a9c20aca8d3bb7c0c87f05e95b7a8808095aa8cfc",
	"rust_elemental/hit": "6529b0f57fbaa7fde1728b68821c67198dc7e0e0c8927251729e4ed62c817dd6",
	"rust_elemental/dead": "6aa6c9c4a030b3a1d1c33acac84ddedd6dc43741bb0ab789c09bbd190f59f81a",
	"pipe_phantom/idle": "b0d7a0a4dc9a2c3efd343fab779467fab9306eb818db6bf18c684775c696f935",
	"pipe_phantom/attack": "dc65ee79c2ce37ffe8ed53432e847120ea93cad4e9e2385ba993a757e8cb180c",
	"pipe_phantom/hit": "1614053543681177fdceecd2360f0e5f9516cb2d54138dba10c025c96ff65be6",
	"pipe_phantom/dead": "e3dff017b9370a78d9bfba85bac0ff3441c9b1bbdeb8c03ca819fbd6bc319ec6",
	"shift_supervisor/idle": "82e3610795c1bd2998d510da0efa49af57af5a08b839a522dc976930aeda5ae6",
	"shift_supervisor/attack": "d1dddd68fb1e84b7f2e94d53c575a0a5205ffa94fe6d19d6b101742ac4b846d2",
	"shift_supervisor/hit": "1d15c53e8fd3220288d6556a5281d6c2f730283c6343d345d1277d4192c91e78",
	"shift_supervisor/dead": "ca88e565a72ee2dd54eea3fe063596517f1b3f749437615a43c7c2e8b7a89d29",
	## cowir-sprites 2026-11-20: 8 more W1/W2 sheets redrawn; castle_warden and shadow_knight share one PNG, so their pins match.
	"adaptive_slime/idle": "3f4b4e80ce253653d044b1f8688858d239ec479e4611b3fdbe3faca2d3560100",
	"adaptive_slime/attack": "312add5117c1b2ad465b7b0b7b655b4ce38020efdbd5ad07cf6b6e2f1614f9f6",
	"adaptive_slime/hit": "e307014291171d6558b68fc4805d82852f82d5d5c83b9498b6bd5942114c291e",
	"adaptive_slime/dead": "95debe1b86b67d9b0d486452637861d8e0bb9c6ba5261394e823b03f9fa484f5",
	"ice_wolf/idle": "07f2359d8cc1f46a056a86e9e54dbf1b0b4226da763e0061cda60ff6b8c57e02",
	"ice_wolf/attack": "0451d5d637138e9cb87e4fe0b207c7db022af4e1bbf2b5096636c9316323cd0f",
	"ice_wolf/hit": "467ebb82e00e0d07f28cb92a31ea84879b45409dcf1e8602879866ef524d66cf",
	"ice_wolf/dead": "2aa444a1c2b16890a4476ed8bc75aaac075fb9115540bf1ffe5350eaf1dce76b",
	"spiteful_crow/idle": "0e9e57ee836c24a8eded242ba246513a0e315eba952919e7fde796e3803ed31d",
	"spiteful_crow/attack": "832b47ded07d4436de97f650811d418c26d4cf282e84237f8bbc7577625a434c",
	"spiteful_crow/hit": "88b724b224ff1b2447b6a0c70a106ee1c7d09e89cf06a68cab3f9b8f9a2bc4a0",
	"spiteful_crow/dead": "30a42e9e36e3a9f8aa9179eb5930dadc8fcb07cef49cb4e707e385de04f21642",
	"specter/idle": "82a3c04cbf88948d3c29fed1347ba00d6a4ac4d8397166a8132363aa62d495a2",
	"specter/attack": "e062057a487c1a50a1f4766b92c1f693d1b50e275bc7c36da25fa03d971611a5",
	"specter/hit": "8c249dc86ffa516464968b7471f20d7393f7c061d683cd4402dedcace97baef5",
	"specter/dead": "26fba4985a9a5eec3a1497ffc071679761669325c42df621a1a3221276db1171",
	"shadow_knight/idle": "e89889f5c9939245b6ed10f92ed3c4944665ca54cabaffc1c6e39f3dea440c95",
	"shadow_knight/attack": "2f8bff2d1849a4aa6fc140fa10ceeb07013f701fc5df7efbd322e9641ad14548",
	"shadow_knight/hit": "fb5ca25d62e696c37133bdc4c1e1e1e1f92a44fc6b361bbe19695c2c360337c1",
	"shadow_knight/dead": "68ae830b781a48a318494eaa7daf65f00ddca4d0f84cf950ba653625657e790e",
	"castle_warden/idle": "e89889f5c9939245b6ed10f92ed3c4944665ca54cabaffc1c6e39f3dea440c95",
	"castle_warden/attack": "2f8bff2d1849a4aa6fc140fa10ceeb07013f701fc5df7efbd322e9641ad14548",
	"castle_warden/hit": "fb5ca25d62e696c37133bdc4c1e1e1e1f92a44fc6b361bbe19695c2c360337c1",
	"castle_warden/dead": "68ae830b781a48a318494eaa7daf65f00ddca4d0f84cf950ba653625657e790e",
	"meta_knight/idle": "ead60c561b06141bb01d4c8af47d4c126db899b4657891501d355e3172c2ed57",
	"meta_knight/attack": "71ecf8d5f2543e9adf7b861b1cce4b72b510eb9f0ed441be14a87d6b83131ed2",
	"meta_knight/hit": "9687e14e9ae7486410a155d2c57603e7398d21cb575cb701449bf437b79ae0ec",
	"meta_knight/dead": "5f6d488ef80ef019d79153b0049c1f66a380347855ce448d60d8a5ea89456fa9",
	"permadeath_reaper/idle": "b06784479ceb038f914db4f3987ecab985f17a239c901f8a980053c69057115d",
	"permadeath_reaper/attack": "b0383a67ea78e22e3a4c2f9e82d0f425c8af0c6201269559642f8dbb4cab0728",
	"permadeath_reaper/hit": "b6f3c6fd08fe7e442385508d4a680ba24ef9ef0332e97d370148857689fc70c8",
	"permadeath_reaper/dead": "d25c26ca951f3358716500db196026e87dd5c04be145df880f8a9925c7bdb5c0",
	## cowir-sprites 2026-11-20: mushroom redrawn; its body is tan with purple outlines, which is what the strips draw.
	"mushroom/idle": "f8a05cc883e9c5c073b35124df9eb96b3aeca2ea1cfcaa6999f6e226544d51f6",
	"mushroom/attack": "9d3bdf07d50a2f15e20cb6d4b5d35fa9f8c53183fb9683dccc99e6d1438485ae",
	"mushroom/hit": "c9780b82b0e8f9e98d35a5e6e129fcea588d83de72c6c73078d5ab70b9ada5ab",
	"mushroom/dead": "65d35c0871e0679c720b129ed3e9fce93456369061faa5e32bebd49b93ef296b",
	## cowir-sprites 2026-11-20: cog_swarm redrawn; told the haze above it is smoke, so no strip grows a smokestack.
	"cog_swarm/idle": "4b0382bc45f90d46728961a3a2ee8690d6b661f2d721180659c8978b2560677c",
	"cog_swarm/attack": "089c8d05e7d9b76bad8752cd471857aa839eff0a223dedb321dc9308f88acf21",
	"cog_swarm/hit": "b6ab6163491d9523ab226db99b1a07fdc861edddb9857c30f6c639464577a465",
	"cog_swarm/dead": "3ef9b1b1742d998fab6c968fef8afe54f0aa0c1b1200b478347cb0802288f5b3",
	## cowir-sprites 2026-11-20: 7 W4 digital sheets redrawn on grey; data_wraith and firewall_sentinel keep their shipped one-frame idle (regen frame 1 overlapped it 64-65%).
	"corrupted_sprite/idle": "26869349d6b0968b0d81f33d07ed376f27a8ed08704a3135ab3609b39cf05c5b",
	"corrupted_sprite/attack": "13f9ab914ca51a8871b716d4fee4b1f492f7b02e665cbe1a4a672f4abc87a727",
	"corrupted_sprite/hit": "95ab29eee048328027d605ca30cce952f49e683ad5d04874415917893523ec16",
	"corrupted_sprite/dead": "7e122e30f71510f12688d613a4d986d675b4131e77aa06efd3c365a03444c446",
	"data_wraith/idle": "3dadc2b65fbd30d77037ebf404a8617083f15e480fcbb156aa6f8d17e2dbb3db",
	"data_wraith/attack": "93ae45199a1072390f46fb1ca95172e7e691a3c62348c573c59f00546b149a40",
	"data_wraith/hit": "4a7036e3055c524d00208d80c355cb42291d13bb52bf078755c3fbb70d44ce18",
	"data_wraith/dead": "d56815533fcea92b05b9db5b00dd297691e8af1ad6f7b606382a9ecfd57b8f9a",
	"firewall_sentinel/idle": "0a50e5d83ee065048f26d0e48690c65cfe05fd02190c255da9cd0606881a1bf3",
	"firewall_sentinel/attack": "f23464407f9c0bc543867d9535ebac5b1259531207603818f84e3239939a5f62",
	"firewall_sentinel/hit": "9f65976f9671080bed98072df38ce52bd17a9e6ce8653626c85967bd46e26f8a",
	"firewall_sentinel/dead": "51f2e5e228371d0468c2f44ce67d572d4b7f2aa65d2c137a427ac7524c492191",
	"glitch_entity/idle": "bd0033d874af9aa36a45709415d2ec4790ffe0b17a130bcbcfd89b1158dd95df",
	"glitch_entity/attack": "b3ba504dd208917fc5f613af8073278fef602578b3ff2bae79cf88768649809b",
	"glitch_entity/hit": "f67158782956faafd7358727015fa7bf8ca73bfcf07e82b0c7b28f0a731edbe4",
	"glitch_entity/dead": "a2e53ec537c3a89ab060b2451b3aef64c8cf1b833f793d87e5bdae9ab3b47e01",
	"memory_leak/idle": "203f9f0d6f8c4585d0e62b06655ff7c28bb1c4532337f84a6ee9a5b4d70ffd6b",
	"memory_leak/attack": "b24d4c3da92b5b32b630f7b592c131ff6f99854fe205bac8b0cdc88e8be936b4",
	"memory_leak/hit": "b6ec5b980f7ae06c07192a27bb1b13c559d141594f8240a2131c842b84a99dd5",
	"memory_leak/dead": "9450eb56e0961ba80ddfb64ffb86da24b18015adde69b64c1c81fc53bee692a1",
	"rogue_process/idle": "3d8bb05c72dc06fc5f3fd1b63c41689867993cc7a5c1d9a419af448099220a90",
	"rogue_process/attack": "b1e02534f92a5fce284a957df286ac29a14d4578c84a993287a2520809692437",
	"rogue_process/hit": "21e488ea0257eaf016be3ee0beb9a292b4e15b57777816e3eabecd3f7c966b00",
	"rogue_process/dead": "2ae5aa05b9e38a8c23b02cb7cc8b5a936612e59e752c9c486cb7be86fb9c9455",
	"script_error/idle": "268848451ff37068cf716a8e2a3396390d674576cd04d8d8cab682213585b73c",
	"script_error/attack": "c1dc868bd02ff203ed866c0378e4b676933f97a3e59dc8ac6f7f4ae8785cbd67",
	"script_error/hit": "d29bf6f77b7fedab1673f6b8f5442ec84b4e6994f774baba2e3aa2c01c2e88ac",
	"script_error/dead": "01fe86c8a78b500495b04909ae495ed063c7e3a6a4c5f247dfdd5d5e7d55a41d",
	## cowir-sprites 2026-11-20: 7 that idled as a void redrawn on grey; idle frame 1 checked against the 0.70 idle floor (lowest 0.737).
	"corrupted_guardian/idle": "a0f0cb6540590b0ec1a2dac635dba5ea9cf4010b37c3d02bfdd0ef4760f65e26",
	"corrupted_guardian/attack": "3a95bbe8be020c8b64573b0fff06e0b83b7e97185fa8929a6a7da30a5f5f5f87",
	"corrupted_guardian/hit": "ac9cd67905631aa9d56b7137a51642235dde32daa4c1e36e649073de34e34a6b",
	"corrupted_guardian/dead": "389f65d4ebc3caed1005c2aaf8c199cf8a8c50320633b08d51927071ff76d581",
	"crystal_golem/idle": "e3cda4bd102cc401cb70fb041c249ac31a472dfe08747ebf2c4afb73d8f3b70b",
	"crystal_golem/attack": "efe65cea2f59b558780e22868b5652cef73ef665a903ae15ce2f21feb95d690b",
	"crystal_golem/hit": "288aa1a3c9799c5267208e57f9833573317a5e5a0a3a366614f253914cde6a8c",
	"crystal_golem/dead": "5446898fa01ae7ba13d4b5e32971c9b001f06bdf08e512bd8df032b77975aafa",
	"empty_set/idle": "3ef12713ad8440954eea54d4ce4f5f7bfcdbf91e7f65f5b2b2021ed0faf03204",
	"empty_set/attack": "cee96711d14df0aa7d0ed8b751d7f6d62c6db50afe26d97f05a832b3931160bd",
	"empty_set/hit": "3fa56fc193635b3713f53b91d48b2a7baacd4d58625cf4259d85c9d36722585a",
	"empty_set/dead": "1e22ca4480b26600efa3c3d3a89559351fc2cac9ae899021639d2bc692ae4e02",
	"forgotten_variable/idle": "1f850cd6f1d8b59d7a223b82aae18b09312660a709f5b3a52be388fbe5f0eaa0",
	"forgotten_variable/attack": "979b8e5962a64acd3d30376ff659eb585e9da0b85af3d46a91523ad3bd62156e",
	"forgotten_variable/hit": "cf48a3bc7649567950bad4240b7d1c2a75502006e624bfe8e9635e067312e78c",
	"forgotten_variable/dead": "81c4ebdc6fe7ac32223604bd00d7b39b28d477b4b03647af4ede514a4f691201",
	"null_entity/idle": "3f865265239e9a159e3cbe472e1cd5fa8f9aef395fe26c81cc96865817423346",
	"null_entity/attack": "6287dbb68757be69393673bbd7466a331ec0828421925ff9800a734d53840834",
	"null_entity/hit": "a82e141f54b85a20a6cc3c40a4b2970f10c3376958fdb61b680de3f2c7dce653",
	"null_entity/dead": "325915f502485aa58e52d92b9b72da9194744b7ac7658edc3d3ae31984a158a9",
	"optimization_itself/idle": "4bf47e3084b9b18ff07cf9620c34f439a5a2fa40ed590e98b2d4363faa6ab70f",
	"optimization_itself/attack": "f8a89a29505ba126927ecf9ada4b267227d8c7abf3ed51bc948fb917d420ce1e",
	"optimization_itself/hit": "7a34c66923d60254a964194ce492ff262afef40d57ecb7c2ec792050c9ad9dfd",
	"optimization_itself/dead": "e06035e7cd2ee29f9a0cd5d3def5d903fcbd676081e8aaece35906f5af0b8879",
	"the_absence/idle": "132d4f4d97567f25f8289e10065a0fa3fc5063d053222e98917a88d2eedfdc84",
	"the_absence/attack": "09983288294c1508ae96a760acccd37e107578afbadc3d38d9d167225b51af7e",
	"the_absence/hit": "af78be3e7ffbea812f52af88a28994af72416efbc4ecb072eb0a723c925c0872",
	"the_absence/dead": "0892b99bdc575911ab304f9684dc82d7bc8f8903e9f813f41419f5eab6777266",
	"masterite_arbiter_futuristic/idle": "222ff9212a816df1b9d675903a073557b36f5ff2349f769a1bbc0b2ea59dabbf",
	"masterite_arbiter_futuristic/attack": "36c2d1e8385cd5b81da32dc15ff95d169d15767ea38797cfdfde8732ed73c5c8",
	"masterite_arbiter_futuristic/hit": "4cba32d85f5b5e571016bfb03780b99515d9bb254fcce77d92183774ed8cc984",
	"masterite_arbiter_futuristic/dead": "8e9b51422ddf79c106b68b35f6996181331f6cef25ce8b11f32832ae383bd3ac",
	"masterite_tempo_futuristic/idle": "c1894ec744cabaeb4c55d9638380007f69ca7333461cbe649d0d4410952ca59a",
	"masterite_tempo_futuristic/attack": "ff7b9f3cca0dea40d85da6076148530a9733f09591fdca96f7b920e0671ca660",
	"masterite_tempo_futuristic/hit": "3c97c7faf39c61571c2821478bd2a98e3f6830056d5b8a5afde75c64795aa32f",
	"masterite_tempo_futuristic/dead": "0448b963f3fd3b18fc7798ca71f4b57dbbf22872b3261e64fae9983121c17269",
	"masterite_warden_abstract/idle": "aab7bcb245b17f3d75283d9726a254a0f1f9806afcde100f784479bc19c921eb",
	"masterite_warden_abstract/attack": "d6879c2326b1994fa09ea88ca4cc3d4c51799f948949cbebe23bf62678960fe8",
	"masterite_warden_abstract/hit": "75e4675289deca5c7b267a0a508a75c3e6d924047f544225e5db8581519b92b9",
	"masterite_warden_abstract/dead": "59d587966845d423188b1c893ba5c24d4727d70c6d0e958871ae338135366057",
	"masterite_warden_futuristic/idle": "ae5a252e63ea281504072f0843fd39667e18d3b9fdee5421893977e503b85967",
	"masterite_warden_futuristic/attack": "b07fdc91f7d9791b393dccc06dfa04b490a694a7099f058fa7320b4b8e2d5d07",
	"masterite_warden_futuristic/hit": "f223b8f5fc453a64dd7587745d8b7067a41e4d5ac44a2ba7165c927f8533dacd",
	"masterite_warden_futuristic/dead": "409aa47a12c02bf570ed14f3e404162ca3cf565f0bb8c124db246ecdffe621b8",
	"masterite_arbiter_abstract/idle": "ad85238ced2f7f7eb2a99411d1b031a979e16b56c12bb3d9f1f235f1e72c98cd",
	"masterite_arbiter_abstract/attack": "89bc4bbdc94f67334d36c662ca78a0bd63c0722cc3b5b4baf8135f2044c6f3b3",
	"masterite_arbiter_abstract/hit": "53b40ed237be67aa2722dd8bcc33194e2f56968b62c8a6fa816c7adc27505636",
	"masterite_arbiter_abstract/dead": "8f14d212dc507c717ea8de317ea010267c53c8c01891a219101f0ba74fad2fc1",
	"masterite_arbiter_industrial/idle": "45c4275f1ee4afb0ecc2424f05e2299513791c0c3c755d07ef207497c6390af6",
	"masterite_arbiter_industrial/attack": "61fb2588c1f800661e20c51195719abf3b8cbc881cd4365e89b87a78498cf2ac",
	"masterite_arbiter_industrial/hit": "904aa288b9b8bcdbdbe5d3e5c6dc11a3f05006031fe1ade2073a61dbf97e8614",
	"masterite_arbiter_industrial/dead": "1af8001f902e344d2cac3850ec33cf722df44628feaef63942066c78fe6ae949",
	"masterite_arbiter_medieval/idle": "6bf7052081f480b85ffd0e31c33e10ed176a402eb18f9156ae254195144d1389",
	"masterite_arbiter_medieval/attack": "488ca5371624a88332661aeebb727d60f3832be65ee9e4f168c77b6d7bcb0944",
	"masterite_arbiter_medieval/hit": "94e21dd4fa41ff7809be018cef6a05040a68125a4ee912d2d50bf170627df5c3",
	"masterite_arbiter_medieval/dead": "adb1e244dbda913012bb22ca26ede80946c66f831b0c3803499a3e9ce7cd6491",
	"masterite_arbiter_suburban/idle": "438bb5e2eda529747871938e242e73dbb21dabb758bb9b79b3dedd1ce1d947a7",
	"masterite_arbiter_suburban/attack": "f6923208322e91ac892a62902ba37675c1c2704b00e68e626277a9f67f7802b3",
	"masterite_arbiter_suburban/hit": "d1fc9d205da2b85eb1a149fde2830bb9fa8f9753130e207fee989e564209f41d",
	"masterite_arbiter_suburban/dead": "8f58fcdbc17d19e400792ec3c77b03d0cc57236323b7e024c3d86f0b1cad8ee9",
	"masterite_curator_futuristic/idle": "da4434bdbc81477cdb161d73bdbc7be46573e75c053956a2669fd956dc639b09",
	"masterite_curator_futuristic/attack": "f32b735be0ad108064c44d21ac99c5da27a3ff540a4371a8fe3d3c6752aea98f",
	"masterite_curator_futuristic/hit": "510dde25af70c1e5af9b0beb7da5854c30f0b57aa606077c9ed4b3510be4fcff",
	"masterite_curator_futuristic/dead": "c3d370ec725f910906e31f4d201fd8cd18a9efa3badb01b8290e73072e7fb656",
	"masterite_curator_industrial/idle": "16fa79f7904a52a31ce11ad5fa58127ecbf64440f957b51c4e0fefa0cae4905d",
	"masterite_curator_industrial/attack": "41925eb3a15d766e655dd8200c68c68bfbdd00e466ee4f432d74bf948a8863fb",
	"masterite_curator_industrial/hit": "581dba7ce69aa253d79bdf4e798751d67a0e9a967d23042476ec68c1ff55da73",
	"masterite_curator_industrial/dead": "dedfb0adba7c5bf929b7bdf238cabc17abb927b47c6bba5f2776ffbf9341e27c",
	"masterite_curator_medieval/idle": "18fc34cb2a349227f611ac7866bb4e8e34943c4d71985dfce505202acf62af56",
	"masterite_curator_medieval/attack": "4a4ba962f8672e9119a176e787261872c26b0a002f0b400b00c98837646f6701",
	"masterite_curator_medieval/hit": "87e31ad08fd4227ab2b7146038d7bf98ed55c7bcc1b532c3cab02eea7d8a7da3",
	"masterite_curator_medieval/dead": "f78edc5eb4dfff854385f06e6044b9c623121c6710d758ee5656b5d4be32cfd6",
	"masterite_curator_suburban/idle": "0520f17f84131663460eb78ca236bf19e64cadd63bfae9f170b356d97354aacd",
	"masterite_curator_suburban/attack": "ee7886f3a9f4d535e14d7c4933d90a1f6c5aa51ad414b60724ee28437da5234e",
	"masterite_curator_suburban/hit": "97bd83e93360df659f30cd090d499d5fdb0940a1de9e9c0e2fde1890cc9307cb",
	"masterite_curator_suburban/dead": "9958c08407ca0b7392a72dcd9e008861afd610e7350611456b38431d6f590d49",
	"masterite_tempo_industrial/idle": "ebb95f9177bdadf56ef4b0eaa37f3703a723682f4d516d817a4bb5e22d27085d",
	"masterite_tempo_industrial/attack": "2620a06fe3fb852e5c18a2c6fee5964565d6f34f567de4904cae8fdac0457106",
	"masterite_tempo_industrial/hit": "b10d262d1461c9b7e1c2e9dcefc9869846ae47202e7a1946401bb8a5fbf33784",
	"masterite_tempo_industrial/dead": "348e5f49b8e63ebd7df7be146c6b8ab293477b7435e02e04aeb55f1b779b8a01",
	"masterite_tempo_medieval/idle": "b688aaa6e15d6ecdae0d1fb289f12be3281bb6e15d24c78cb5a5ceec275fe07e",
	"masterite_tempo_medieval/attack": "cc247a72b20d9c3676bb3d6fba80720ebdf5baf9b89675b2a4d14367aa41cd90",
	"masterite_tempo_medieval/hit": "fa74f8a7bda0c32f0b23a974db313df1d0bc71651e2881676722527d6f42712d",
	"masterite_tempo_medieval/dead": "f2378e7984c36df65a423326c2995865752dfe9a873bd01d211f7453431b747e",
	"masterite_tempo_suburban/idle": "fe0c939a78a1fa369906196eab0662b4b0bdbba693b974cd9ab81bce2b2ca2cb",
	"masterite_tempo_suburban/attack": "ce4ad5fb165931b9ea4df71d6d907fcfbcd2616243b47bb716a68bf0716283e5",
	"masterite_tempo_suburban/hit": "88f58de0231379cd304663a842f48ed64e3dc2a8e7484e8ec970bca2474bf305",
	"masterite_tempo_suburban/dead": "766eb43fd7bf5aa5d26e79a8f1e67be8d6c34954e74bac3d7aec0a212af9ce62",
	"masterite_warden_industrial/idle": "82cb5bfff0698d70d414191a82f1ac2145b1b2f822bfca660781de0257d86810",
	"masterite_warden_industrial/attack": "26e355f8f3ea3a75102e6418cd4bdd979a872899470282f614bdbf815eea774c",
	"masterite_warden_industrial/hit": "92ccc8115294f47cd11f8c77483d8745e6e75002148524f13a778d21e047398d",
	"masterite_warden_industrial/dead": "fed4bc7fe4cc4eeebb9ddf0c7891d9f8efb5bc182936a0c7cbb53e7e726dfd57",
	"masterite_warden_medieval/idle": "d32681d8a0586dccd6216beb632f480a0d2a6839aa9e5baa840975f82523b109",
	"masterite_warden_medieval/attack": "4669b25a4754467126aa45a037833781da13b38ba72986d6d4d14881d82d6f34",
	"masterite_warden_medieval/hit": "1d1f450499c0f068d1096c7d208d4092d225f79e70d7123a18634c51867ea67b",
	"masterite_warden_medieval/dead": "217ca60a98d59d2d77f0204cf705014e61cff75077954b8b315532c410571b1b",
}
## Redrawn from their own idle by the paid S4 motion regen (tools/install_motion_regen.py, $0): off the repoint list, every range eye-pinned.
const REDRAWN_BY_MOTION_REGEN := [
	"troll", "unassuming_dog", "cave_rat_king", "snake", "viper", "toxic_sludge", "cranky_lady", "skate_punk",
	"new_age_retro_hippie", "treasure_mimic", "fungoid", "diseased_rat", "elder_mushroom", "giant_bat",
	"blood_wolf_alpha", "steam_rat", "conveyor_gremlin",
	"brass_golem", "clockwork_sentinel", "assembly_line_automaton", "ironback_beetle", "rust_elemental", "pipe_phantom",
	"shift_supervisor", "adaptive_slime", "ice_wolf", "spiteful_crow", "specter", "shadow_knight", "castle_warden",
	"meta_knight", "permadeath_reaper", "mushroom", "cog_swarm",
	"corrupted_sprite", "data_wraith", "firewall_sentinel", "glitch_entity", "memory_leak", "rogue_process", "script_error",
	"corrupted_guardian", "crystal_golem", "empty_set", "forgotten_variable", "null_entity", "optimization_itself", "the_absence",
	"masterite_arbiter_futuristic", "masterite_tempo_futuristic", "masterite_warden_abstract", "masterite_warden_futuristic",
	"masterite_arbiter_abstract", "masterite_arbiter_industrial", "masterite_arbiter_medieval", "masterite_arbiter_suburban",
	"masterite_curator_futuristic", "masterite_curator_industrial", "masterite_curator_medieval", "masterite_curator_suburban",
	"masterite_tempo_industrial", "masterite_tempo_medieval", "masterite_tempo_suburban",
	"masterite_warden_industrial", "masterite_warden_medieval",
]
## A redrawn frame's colours against its idle: measured min 0.697 (the thin snake's lunge); another species scores lower.
const REDRAWN_COLOUR_FLOOR := 0.65
const ONE_CREATURE_BY_REPOINT := [
	"cursed_armor", "elemental", "masterite_warden_suburban", "recursive_loop", "the_margin",
]


func _sheets() -> Dictionary:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_manifest.json"))
	return manifest["monster_sheets"]


func _image(entry: Dictionary) -> Image:
	var img: Image = (load(str(entry["path"])) as Texture2D).get_image().duplicate()
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


func _masks(entry: Dictionary, img: Image = null) -> Array:
	## One PackedByteArray per frame of the sheet: 1 where the pixel is solid.
	if img == null:
		img = _image(entry)
	var fw := int(entry["frame_width"])
	var h := img.get_height()
	var d := img.get_data()
	var out: Array = []
	for i in range(img.get_width() / fw):
		var m := PackedByteArray()
		m.resize(fw * h)
		for y in h:
			for x in fw:
				m[y * fw + x] = 1 if d[(y * img.get_width() + i * fw + x) * 4 + 3] >= 128 else 0
		out.append(m)
	return out


static func overlap(a: PackedByteArray, b: PackedByteArray) -> float:
	var both := 0
	var either := 0
	for i in a.size():
		both += 1 if a[i] and b[i] else 0
		either += 1 if a[i] or b[i] else 0
	return float(both) / maxf(1.0, float(either))


func _best_idle_overlap(masks: Array, idle: Dictionary, i: int) -> float:
	var best := 0.0
	for j in range(int(idle["start"]), int(idle["end"]) + 1):
		best = maxf(best, overlap(masks[i], masks[j]))
	return best


func _colour_hist(img: Image, fw: int, i: int) -> PackedFloat32Array:
	var shift := 8 - COLOUR_BITS
	var h := PackedFloat32Array()
	h.resize(1 << (3 * COLOUR_BITS))
	var d := img.get_data()
	var n := 0
	for y in img.get_height():
		for x in fw:
			var o := (y * img.get_width() + i * fw + x) * 4
			if d[o + 3] < 128:
				continue
			h[((d[o] >> shift) << (2 * COLOUR_BITS)) | ((d[o + 1] >> shift) << COLOUR_BITS) | (d[o + 2] >> shift)] += 1.0
			n += 1
	for k in h.size():
		h[k] /= maxf(1.0, float(n))
	return h


static func colour_match(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var s := 0.0
	for k in a.size():
		s += minf(a[k], b[k])
	return s


func _png(entry: Dictionary) -> Image:
	## The sheet's PNG bytes, not its import: fix_alpha_border repaints faint edge pixels, so a soft legacy idle hashes differently.
	var img := Image.new()
	img.load_png_from_buffer(FileAccess.get_file_as_bytes(str(entry["path"])))
	img.convert(Image.FORMAT_RGBA8)
	return img


func _range_hash(img: Image, fw: int, r: Dictionary) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for i in range(int(r["start"]), int(r["end"]) + 1):
		var d := img.get_region(Rect2i(i * fw, 0, fw, img.get_height())).get_data()
		for o in range(0, d.size(), 4):
			if d[o + 3] == 0:
				d[o] = 0
				d[o + 1] = 0
				d[o + 2] = 0
		ctx.update(d)
	return ctx.finish().hex_encode()


## Why frame i of `anim` may not ship, given it is under MIN_OVERLAP; "" = it ships on eye + colour.
func _motion_refusal(key: String, anim: String, img: Image, entry: Dictionary, i: int) -> String:
	if anim in OVERLAP_ONLY_ANIMS:
		return "under the overlap floor, and %s is not a motion" % anim
	var fw := int(entry["frame_width"])
	var idle: Dictionary = entry["animations"]["idle"]
	var mine := _colour_hist(img, fw, i)
	var best := 0.0
	for j in range(int(idle["start"]), int(idle["end"]) + 1):
		best = maxf(best, colour_match(mine, _colour_hist(img, fw, j)))
	if best < COLOUR_FLOOR:
		return "colour %.3f under %.2f" % [best, COLOUR_FLOOR]
	if str(EYE_REVIEWED.get("%s/%s" % [key, anim], "")) != _range_hash(img, fw, entry["animations"][anim]):
		return "nobody has looked at these pixels (no EYE_REVIEWED pin matches)"
	return ""


func test_a_listed_monster_shows_one_creature_in_every_live_frame() -> void:
	var sheets := _sheets()
	var strays: Array = []
	var still_has_the_defect := 0
	for key in ONE_CREATURE_BY_REPOINT:
		assert_true(sheets.has(key), "CONTROL: %s is a monster sheet" % key)
		if not sheets.has(key):
			continue
		var entry: Dictionary = sheets[key]
		var img := _image(entry)
		var masks := _masks(entry, img)
		var idle: Dictionary = entry["animations"]["idle"]
		var live := {}
		for anim in entry["animations"]:
			var r: Dictionary = entry["animations"][anim]
			for i in range(int(r["start"]), int(r["end"]) + 1):
				live[i] = true
				if _best_idle_overlap(masks, idle, i) < MIN_OVERLAP:
					var why := _motion_refusal(key, anim, img, entry, i)
					if why != "":
						strays.append("%s %s frame %d: %s" % [key, anim, i, why])
		for i in masks.size():
			if not live.has(i) and _best_idle_overlap(masks, idle, i) < MIN_OVERLAP:
				still_has_the_defect += 1
				break
	## CONTROL: the other creatures are still in the PNGs, so naming one of those frames again would red the arm above.
	assert_eq(still_has_the_defect, ONE_CREATURE_BY_REPOINT.size(),
		"every listed sheet still holds an unused frame of another creature (a redrawn sheet comes OFF the list)")
	assert_eq(strays, [], "listed monsters that still turn into something else: %s" % str(strays))


func test_the_measure_sees_an_artist_monster_move() -> void:
	## CONTROL: the artist's bat really animates, so its attack is not its idle picture, and it is still one creature.
	var entry: Dictionary = _sheets()["bat"]
	var masks := _masks(entry)
	var a: Dictionary = entry["animations"]["attack"]
	var worst := 1.0
	for i in range(int(a["start"]), int(a["end"]) + 1):
		worst = minf(worst, _best_idle_overlap(masks, entry["animations"]["idle"], i))
	assert_lt(worst, 0.999, "the bat's attack differs from its idle (%.3f)" % worst)


func test_a_motion_frame_ships_on_eye_and_colour_and_a_swap_still_reds() -> void:
	var entry: Dictionary = _sheets()["cave_rat_king"]
	var img := _image(entry)
	var masks := _masks(entry, img)
	var r: Dictionary = entry["animations"]["royal_spite"]
	for i in range(int(r["start"]), int(r["end"]) + 1):
		assert_lt(_best_idle_overlap(masks, entry["animations"]["idle"], i), MIN_OVERLAP,
			"CONTROL: royal_spite frame %d is a real lunge, under the overlap floor, so eye + colour is what passes it" % i)
		assert_eq(_motion_refusal("cave_rat_king", "royal_spite", img, entry, i), "", "the reviewed lunge ships")
	var at := int(r["start"]) * 256
	var dog: Dictionary = _sheets()["unassuming_dog"]
	var swapped := img.duplicate() as Image
	swapped.blit_rect(_image(dog), Rect2i(int(dog["animations"]["idle"]["start"]) * 256, 0, 256, 256), Vector2i(at, 0))
	assert_string_contains(_motion_refusal("cave_rat_king", "royal_spite", swapped, entry, int(r["start"])), "colour",
		"a different species' frame in the lunge must red on colour")
	var own_kin := img.duplicate() as Image
	own_kin.blit_rect(img, Rect2i(4 * 256, 0, 256, 256), Vector2i(at, 0))
	var why := _motion_refusal("cave_rat_king", "royal_spite", own_kin, entry, int(r["start"]))
	assert_false(why.contains("colour"), "CONTROL: his own hit frame 4 is a rat king in his palette and passes colour (%s)" % why)
	assert_string_contains(why, "looked", "so the eye pin is what refuses a same-palette swap")
	assert_ne(_motion_refusal("cave_rat_king", "dead", img, entry, int(r["start"])), "",
		"dead keeps the overlap floor; only motion ships on eye + colour")


func test_a_redrawn_monster_ships_only_the_frames_someone_looked_at() -> void:
	var sheets := _sheets()
	var unseen: Array = []
	var off_colour: Array = []
	for key in REDRAWN_BY_MOTION_REGEN:
		assert_true(sheets.has(key), "CONTROL: %s is a monster sheet" % key)
		assert_false(key in ONE_CREATURE_BY_REPOINT, "%s is redrawn, so it is off the repoint list" % key)
		if not sheets.has(key):
			continue
		var entry: Dictionary = sheets[key]
		var img := _image(entry)
		var src := _png(entry)
		assert_eq(src.get_size(), img.get_size(), "CONTROL: %s's PNG decoded at its imported size" % key)
		var fw := int(entry["frame_width"])
		var idle: Dictionary = entry["animations"]["idle"]
		for anim in ["idle", "attack", "hit", "dead"]:
			var r: Dictionary = entry["animations"][anim]
			assert_eq(int(r["end"]) - int(r["start"]), 1, "%s %s plays two frames again, not the idle picture" % [key, anim])
			if str(EYE_REVIEWED.get("%s/%s" % [key, anim], "")) != _range_hash(src, fw, r):
				unseen.append("%s/%s" % [key, anim])
			for i in range(int(r["start"]), int(r["end"]) + 1):
				var best := 0.0
				for j in range(int(idle["start"]), int(idle["end"]) + 1):
					best = maxf(best, colour_match(_colour_hist(img, fw, i), _colour_hist(img, fw, j)))
				if best < REDRAWN_COLOUR_FLOOR:
					off_colour.append("%s frame %d: %.3f" % [key, i, best])
	assert_eq(unseen, [], "redrawn ranges whose pixels nobody looked at (re-pin after an eye check): %s" % str(unseen))
	assert_eq(off_colour, [], "redrawn frames off their idle's colours: %s" % str(off_colour))


func test_a_species_swap_into_a_redrawn_range_reds_on_both_checks() -> void:
	var troll: Dictionary = _sheets()["troll"]
	var dog: Dictionary = _sheets()["unassuming_dog"]
	var img := _image(troll)
	var r: Dictionary = troll["animations"]["attack"]
	assert_eq(str(EYE_REVIEWED["troll/attack"]), _range_hash(img, 256, r), "CONTROL: the shipped troll attack is the pinned one")
	img.blit_rect(_image(dog), Rect2i(0, 0, 256, 256), Vector2i(int(r["start"]) * 256, 0))
	assert_ne(str(EYE_REVIEWED["troll/attack"]), _range_hash(img, 256, r), "a dog in the troll's attack breaks the eye pin")
	var best := 0.0
	for j in range(int(troll["animations"]["idle"]["start"]), int(troll["animations"]["idle"]["end"]) + 1):
		best = maxf(best, colour_match(_colour_hist(img, 256, int(r["start"])), _colour_hist(img, 256, j)))
	assert_lt(best, REDRAWN_COLOUR_FLOOR, "and falls under the colour floor (%.3f)" % best)
