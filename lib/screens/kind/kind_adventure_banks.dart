import 'kind_game_banks.dart';
import 'kind_game_question.dart';

/// Extra educational adventure banks (joined with the original kid games).

List<GameQuestion> buildAlphabetAdventure() {
  final qs = <GameQuestion>[];
  // Upper ↔ lower matching
  for (var i = 0; i < 26; i++) {
    final upper = String.fromCharCode(65 + i);
    final lower = String.fromCharCode(97 + i);
    final distractors = <String>{};
    while (distractors.length < 3) {
      final d = String.fromCharCode(97 + kidGameRand.nextInt(26));
      if (d != lower) distractors.add(d);
    }
    qs.add(_mcq(
      'Match the uppercase letter!\n$upper → ?',
      lower,
      distractors.toList(),
      speakWord: upper,
      qid: 'aa_case_$upper',
    ));
  }
  // Hidden letter / find the letter
  const words = [
    ('APPLE', 'A'),
    ('BALL', 'B'),
    ('CAT', 'C'),
    ('DOG', 'D'),
    ('EGG', 'E'),
    ('FISH', 'F'),
    ('GOAT', 'G'),
    ('HAT', 'H'),
    ('ICE', 'I'),
    ('JAM', 'J'),
    ('KITE', 'K'),
    ('LION', 'L'),
    ('MOON', 'M'),
    ('NEST', 'N'),
    ('OWL', 'O'),
    ('PEN', 'P'),
    ('QUEEN', 'Q'),
    ('RAIN', 'R'),
    ('SUN', 'S'),
    ('TREE', 'T'),
    ('UP', 'U'),
    ('VAN', 'V'),
    ('WATER', 'W'),
    ('BOX', 'X'),
    ('YARN', 'Y'),
    ('ZEBRA', 'Z'),
  ];
  for (final w in words) {
    final hidden = w.$1.replaceFirst(w.$2, '_');
    final others = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
        .split('')
        .where((l) => l != w.$2)
        .toList();
    qs.add(_mcq(
      'Find the hidden letter:\n$hidden',
      w.$2,
      _pick3(others),
      speakWord: w.$1.toLowerCase(),
      qid: 'aa_hid_${w.$1}',
    ));
  }
  // Phonics starts-with
  const phonics = [
    ('A says /a/ like…', 'Apple', ['Ball', 'Cat', 'Dog']),
    ('B says /b/ like…', 'Ball', ['Egg', 'Ice', 'Owl']),
    ('C says /k/ like…', 'Cat', ['Apple', 'Egg', 'Ice']),
    ('D says /d/ like…', 'Dog', ['Apple', 'Egg', 'Ice']),
    ('M says /m/ like…', 'Moon', ['Sun', 'Tree', 'Fish']),
    ('S says /s/ like…', 'Sun', ['Moon', 'Ball', 'Dog']),
    ('T says /t/ like…', 'Tree', ['Moon', 'Sun', 'Ball']),
    ('P says /p/ like…', 'Pen', ['Owl', 'Ice', 'Egg']),
  ];
  for (final p in phonics) {
    qs.add(_mcq(p.$1, p.$2, p.$3, speakWord: p.$2, qid: 'aa_ph_${p.$2}'));
  }
  return _ensureFifty(qs);
}

List<GameQuestion> buildNumberKingdom() {
  final qs = <GameQuestion>[];
  // Counting & recognition
  for (var n = 1; n <= 20; n++) {
    qs.add(_mcq(
      'What number is this?\n$n',
      '$n',
      _numDistractors(n),
      speakWord: '$n',
      qid: 'nk_rec_$n',
    ));
  }
  for (var a = 1; a <= 10; a++) {
    for (var b = 1; b <= 5; b++) {
      final sum = a + b;
      qs.add(_mcq(
        'Number Kingdom race!\n$a + $b = ?',
        '$sum',
        _numDistractors(sum),
        qid: 'nk_add_${a}_$b',
      ));
      if (a > b) {
        final diff = a - b;
        qs.add(_mcq(
          'Subtract!\n$a − $b = ?',
          '$diff',
          _numDistractors(diff),
          qid: 'nk_sub_${a}_$b',
        ));
      }
      if (qs.length >= 80) break;
    }
    if (qs.length >= 80) break;
  }
  // Multiplication (small)
  for (var a = 2; a <= 5; a++) {
    for (var b = 2; b <= 5; b++) {
      final p = a * b;
      qs.add(_mcq(
        'Multiplication adventure!\n$a × $b = ?',
        '$p',
        _numDistractors(p),
        qid: 'nk_mul_${a}_$b',
      ));
    }
  }
  qs.shuffle(kidGameRand);
  return qs.take(50).toList();
}

List<GameQuestion> buildWordBuilderAdventure() {
  final bank = <(String, String, List<String>)>[
    ('Build the word for a baby dog', 'PUPPY', ['KITTY', 'CUB', 'FOAL']),
    ('Spell the fruit: A _ P L E', 'P', ['B', 'T', 'M']),
    ('Picture: ☀️ → which word?', 'SUN', ['MOON', 'STAR', 'RAIN']),
    ('Picture: 🌳 → which word?', 'TREE', ['FISH', 'BALL', 'BOOK']),
    ('Picture: 🐱 → which word?', 'CAT', ['DOG', 'COW', 'HEN']),
    ('Picture: 🐶 → which word?', 'DOG', ['CAT', 'PIG', 'FOX']),
    ('Missing letter: C _ T', 'A', ['E', 'I', 'O']),
    ('Missing letter: B O O _', 'K', ['P', 'T', 'M']),
    ('Missing letter: F I S _', 'H', ['T', 'R', 'N']),
    ('Build: frozen water is…', 'ICE', ['FIRE', 'SAND', 'SOIL']),
    ('Build: you write with a…', 'PENCIL', ['PLATE', 'PILLOW', 'PIANO']),
    ('Vocabulary: opposite of hot', 'COLD', ['WARM', 'FIRE', 'SUN']),
    ('Vocabulary: a place to learn', 'SCHOOL', ['MARKET', 'BEACH', 'PARK']),
    ('Spell: H A _ P Y', 'P', ['B', 'D', 'G']),
    ('Build: yellow curved fruit', 'BANANA', ['APPLE', 'GRAPE', 'MELON']),
    ('Picture: ⚽ → which word?', 'BALL', ['BOOK', 'BELL', 'BOWL']),
    ('Missing letter: M O O _', 'N', ['P', 'T', 'R']),
    ('Build: animal with a trunk', 'ELEPHANT', ['GIRAFFE', 'TIGER', 'ZEBRA']),
    ('Vocabulary: first meal of day', 'BREAKFAST', ['DINNER', 'SNACK', 'LUNCH']),
    ('Spell: R A I _', 'N', ['M', 'P', 'T']),
    ('Build: flies in the sky', 'BIRD', ['FISH', 'FROG', 'ANT']),
    ('Missing letter: L I O _', 'N', ['P', 'T', 'M']),
    ('Vocabulary: color of grass', 'GREEN', ['BLUE', 'RED', 'PINK']),
    ('Build: you sleep on a…', 'BED', ['DESK', 'CHAIR', 'DOOR']),
    ('Picture: 📚 → which word?', 'BOOK', ['BALL', 'BOX', 'BAG']),
    ('Spell: S T A _', 'R', ['N', 'M', 'P']),
    ('Build: sweet food from bees', 'HONEY', ['SUGAR', 'SALT', 'MILK']),
    ('Missing letter: T I G E _', 'R', ['N', 'S', 'T']),
    ('Vocabulary: water from clouds', 'RAIN', ['SNOW', 'WIND', 'DUST']),
    ('Build: hops with long ears', 'RABBIT', ['TURTLE', 'SNAKE', 'FISH']),
    ('Spell: F R O _', 'G', ['B', 'D', 'P']),
    ('Picture: 🏠 → which word?', 'HOUSE', ['HORSE', 'HILL', 'HUT']),
    ('Missing letter: Q U E E _', 'N', ['R', 'M', 'P']),
    ('Vocabulary: planet we live on', 'EARTH', ['MARS', 'MOON', 'SUN']),
    ('Build: tall animal, long neck', 'GIRAFFE', ['ZEBRA', 'HORSE', 'CAMEL']),
    ('Spell: C L O U _', 'D', ['B', 'P', 'T']),
    ('Build: vehicle that flies', 'PLANE', ['TRAIN', 'BOAT', 'BIKE']),
    ('Missing letter: Z E B R _', 'A', ['E', 'I', 'O']),
    ('Vocabulary: place with many trees', 'FOREST', ['DESERT', 'OCEAN', 'CITY']),
    ('Picture: 🌙 → which word?', 'MOON', ['SUN', 'STAR', 'CLOUD']),
    ('Spell: W A T E _', 'R', ['N', 'M', 'P']),
    ('Build: you wear on your feet', 'SHOES', ['HATS', 'GLOVES', 'SCARF']),
    ('Missing letter: A P P L _', 'E', ['A', 'I', 'O']),
    ('Vocabulary: baby cat', 'KITTEN', ['PUPPY', 'CUB', 'FOAL']),
    ('Build: large gray ocean animal', 'WHALE', ['SHARK', 'DOLPHIN', 'SEAL']),
    ('Spell: T R A I _', 'N', ['M', 'P', 'R']),
    ('Picture: ✏️ → which word?', 'PENCIL', ['PEN', 'PAPER', 'PAINT']),
    ('Missing letter: H O R S _', 'E', ['A', 'I', 'O']),
    ('Vocabulary: soft toy animal', 'TEDDY', ['ROBOT', 'BALL', 'BOOK']),
    ('Build: you open this to enter', 'DOOR', ['WINDOW', 'ROOF', 'WALL']),
  ];
  return bank
      .map((e) => _mcq(e.$1, e.$2, e.$3, speakWord: e.$2, qid: 'wba_${e.$2}_${e.$1.hashCode}'))
      .toList();
}

List<GameQuestion> buildReadingAdventure() {
  final stories = <(String, String, String, List<String>)>[
    (
      'Mia saw a red bird on a tree. The bird sang a happy song.\nWhat did Mia see?',
      'A red bird',
      'bird',
      ['A blue fish', 'A green frog', 'A yellow bee'],
    ),
    (
      'Tom planted a seed. He gave it water every day. Soon a flower grew.\nWhat did Tom plant?',
      'A seed',
      'seed',
      ['A cake', 'A book', 'A toy'],
    ),
    (
      'Lila likes apples. She packed two apples in her bag for school.\nHow many apples did Lila pack?',
      'Two',
      'two',
      ['One', 'Three', 'Four'],
    ),
    (
      'The sun was hot. Ben put on a hat and went to the beach.\nWhere did Ben go?',
      'The beach',
      'beach',
      ['The shop', 'The farm', 'The library'],
    ),
    (
      'A dog named Max ran after a ball. Max wagged his tail.\nWhat is the dog\'s name?',
      'Max',
      'Max',
      ['Sam', 'Rex', 'Buddy'],
    ),
    (
      'Rain fell on the roof. Ana opened her umbrella and smiled.\nWhat did Ana open?',
      'An umbrella',
      'umbrella',
      ['A window', 'A door', 'A book'],
    ),
    (
      'Kofi read a book about stars. At night he looked up at the sky.\nWhat did Kofi look at?',
      'The sky',
      'sky',
      ['The floor', 'The river', 'The stove'],
    ),
    (
      'Sara shared her cookies with her sister. Both girls were happy.\nWhat did Sara share?',
      'Cookies',
      'cookies',
      ['Toys', 'Books', 'Shoes'],
    ),
    (
      'The bus stopped at school. Children jumped out and ran to class.\nWhere did the bus stop?',
      'At school',
      'school',
      ['At the park', 'At home', 'At the zoo'],
    ),
    (
      'A cat slept on a soft mat. Soft snores filled the room.\nWhere did the cat sleep?',
      'On a mat',
      'mat',
      ['On a bed', 'In a box', 'On a chair'],
    ),
  ];
  final qs = <GameQuestion>[];
  for (var i = 0; i < stories.length; i++) {
    final s = stories[i];
    qs.add(_mcq(s.$1, s.$2, s.$4, speakWord: s.$3, qid: 'read_$i'));
  }
  // Pronunciation / hard words
  const hard = [
    ('Tap to hear & choose: which word means big boat?', 'Ship', ['Sheep', 'Shop', 'Shoe']),
    ('Which word means very happy?', 'Joyful', ['Angry', 'Tired', 'Hungry']),
    ('Which word means a baby chicken?', 'Chick', ['Duck', 'Puppy', 'Cub']),
    ('Which word means water falling from clouds?', 'Rain', ['Wind', 'Dust', 'Smoke']),
    ('Which word means a place with many books?', 'Library', ['Kitchen', 'Garage', 'Garden']),
    ('Which word means the opposite of night?', 'Day', ['Dark', 'Moon', 'Star']),
    ('Which word means to move fast?', 'Run', ['Sit', 'Sleep', 'Wait']),
    ('Which word means a yellow fruit monkeys love?', 'Banana', ['Apple', 'Grape', 'Pear']),
    ('Which word means the star we see in daytime?', 'Sun', ['Moon', 'Mars', 'Cloud']),
    ('Which word means a person who teaches?', 'Teacher', ['Doctor', 'Pilot', 'Chef']),
  ];
  for (var i = 0; i < hard.length; i++) {
    final h = hard[i];
    qs.add(_mcq(h.$1, h.$2, h.$3, speakWord: h.$2, qid: 'read_word_$i'));
  }
  // More comprehension fillers
  for (var i = 0; i < 30; i++) {
    final n = (i % 5) + 1;
    qs.add(_mcq(
      'Reading reward check!\nIf you read $n pages, how many pages did you read?',
      '$n',
      _numDistractors(n),
      qid: 'read_rew_$i',
    ));
  }
  return _ensureFifty(qs);
}

List<GameQuestion> buildScienceExplorer() {
  return _ensureFifty([
    _mcq('Which organ pumps blood?', 'Heart', ['Lungs', 'Stomach', 'Brain'],
        qid: 'se_heart'),
    _mcq('We breathe with our…', 'Lungs', ['Ears', 'Knees', 'Hair'],
        qid: 'se_lungs'),
    _mcq('Plants need sunlight to…', 'Grow', ['Sleep', 'Run', 'Talk'],
        qid: 'se_grow'),
    _mcq('A plant grows from a…', 'Seed', ['Rock', 'Cloud', 'Shoe'],
        qid: 'se_seed'),
    _mcq('Fish live in…', 'Water', ['Desert', 'Sky nests', 'Fire'],
        qid: 'se_fish'),
    _mcq('Camels are often found in the…', 'Desert', ['Ocean', 'Rainforest', 'Ice'],
        qid: 'se_camel'),
    _mcq('Penguins like…', 'Cold places', ['Hot deserts', 'Volcanoes', 'Jungles'],
        qid: 'se_peng'),
    _mcq('Rain comes from…', 'Clouds', ['Rocks', 'Trees only', 'Stars'],
        qid: 'se_rain'),
    _mcq('Wind is moving…', 'Air', ['Water only', 'Sand only', 'Fire'],
        qid: 'se_wind'),
    _mcq('The planet we live on is…', 'Earth', ['Mars', 'Venus', 'Jupiter'],
        qid: 'se_earth'),
    _mcq('The Moon goes around the…', 'Earth', ['Sun only', 'Mars', 'Stars'],
        qid: 'se_moon'),
    _mcq('The Sun is a…', 'Star', ['Planet', 'Moon', 'Comet'], qid: 'se_sun'),
    _mcq('Bones help your body to…', 'Stand strong', ['Digest food', 'Pump blood', 'See'],
        qid: 'se_bones'),
    _mcq('We see with our…', 'Eyes', ['Ears', 'Nose', 'Tongue'], qid: 'se_eyes'),
    _mcq('We hear with our…', 'Ears', ['Eyes', 'Feet', 'Hands'], qid: 'se_ears'),
    _mcq('Water that turns to ice is…', 'Freezing', ['Boiling', 'Melting', 'Evaporating'],
        qid: 'se_ice'),
    _mcq('A tadpole grows into a…', 'Frog', ['Fish', 'Bird', 'Snake'],
        qid: 'se_tad'),
    _mcq('Bees help plants by…', 'Pollinating', ['Eating leaves only', 'Making wind', 'Making rain'],
        qid: 'se_bee'),
    _mcq('The sky looks blue because of…', 'Sunlight & air', ['Paint', 'Oceans only', 'Stars'],
        qid: 'se_sky'),
    _mcq('Space exploration uses…', 'Rockets', ['Boats', 'Bicycles', 'Trains'],
        qid: 'se_rocket'),
    _mcq('Astronauts travel in…', 'Space', ['Caves only', 'Deep forests', 'Deserts only'],
        qid: 'se_astro'),
    _mcq('Roots of a plant take in…', 'Water', ['Sound', 'Light only', 'Air only'],
        qid: 'se_root'),
    _mcq('Leaves help plants make…', 'Food', ['Music', 'Sand', 'Clouds'],
        qid: 'se_leaf'),
    _mcq('A habitat is where an animal…', 'Lives', ['Cooks', 'Reads', 'Drives'],
        qid: 'se_hab'),
    _mcq('Whales live in the…', 'Ocean', ['Desert', 'Mountain peak', 'Forest floor'],
        qid: 'se_whale'),
    _mcq('Thunder comes after…', 'Lightning', ['Snow only', 'Sunrise only', 'Moonrise'],
        qid: 'se_thunder'),
    _mcq('Your brain helps you to…', 'Think', ['Digest only', 'Pump blood', 'Breath only'],
        qid: 'se_brain'),
    _mcq('Skin helps protect your…', 'Body', ['Shoes', 'Books', 'Toys'],
        qid: 'se_skin'),
    _mcq('Stars are huge balls of…', 'Hot gas', ['Ice', 'Rock only', 'Water'],
        qid: 'se_stars'),
    _mcq('Earth goes around the…', 'Sun', ['Moon', 'Mars', 'Comets'],
        qid: 'se_orbit'),
    _mcq('Soil helps plants…', 'Grow', ['Fly', 'Sing', 'Swim'], qid: 'se_soil'),
    _mcq('Magnets can attract…', 'Iron', ['Wood', 'Plastic', 'Paper'],
        qid: 'se_mag'),
    _mcq('Ice melts into…', 'Water', ['Steam only', 'Sand', 'Air'],
        qid: 'se_melt'),
    _mcq('A volcano can erupt…', 'Lava', ['Snow cones', 'Cotton', 'Books'],
        qid: 'se_vol'),
    _mcq('Insects usually have how many legs?', '6', ['4', '8', '2'],
        qid: 'se_legs'),
    _mcq('Birds have…', 'Feathers', ['Fur only', 'Scales only', 'Shells'],
        qid: 'se_feather'),
    _mcq('The human body needs…', 'Food & water', ['Only toys', 'Only screens', 'Only shoes'],
        qid: 'se_need'),
    _mcq('Weather that is very wet is…', 'Rainy', ['Sunny only', 'Snowy only', 'Windy only'],
        qid: 'se_weather'),
    _mcq('Night comes when Earth…', 'Turns away from the Sun', ['Stops', 'Melts', 'Freezes'],
        qid: 'se_night'),
    _mcq('Recycling helps the…', 'Earth', ['Moon', 'Mars', 'Stars'],
        qid: 'se_recycle'),
    _mcq('Teeth help us to…', 'Chew food', ['Breathe', 'See', 'Hear'],
        qid: 'se_teeth'),
    _mcq('Exercise makes muscles…', 'Stronger', ['Weaker', 'Blue', 'Silent'],
        qid: 'se_exercise'),
    _mcq('Germs are tiny and can make you…', 'Sick', ['Fly', 'Glow', 'Shrink'],
        qid: 'se_germ'),
    _mcq('Washing hands helps stop…', 'Germs', ['Rain', 'Wind', 'Sunshine'],
        qid: 'se_wash'),
    _mcq('A telescope helps us see…', 'Far objects', ['Tiny sounds', 'Smell', 'Taste'],
        qid: 'se_tele'),
    _mcq('The largest planet near us in night talks is often…', 'Jupiter', ['Earth moon dust', 'A rock', 'A kite'],
        qid: 'se_jup'),
    _mcq('Shadows appear when light is…', 'Blocked', ['Eaten', 'Painted', 'Forgotten'],
        qid: 'se_shadow'),
    _mcq('Electricity can power a…', 'Lamp', ['Cloud', 'Mountain', 'River'],
        qid: 'se_elec'),
    _mcq('A thermometer measures…', 'Temperature', ['Speed only', 'Weight of stars', 'Colors'],
        qid: 'se_therm'),
    _mcq('Living things need energy from…', 'Food', ['Rocks only', 'Plastic', 'Metal'],
        qid: 'se_energy'),
  ]);
}

List<GameQuestion> buildGeographyExplorer() {
  return _ensureFifty([
    _mcq('Nigeria\'s capital is…', 'Abuja', ['Lagos', 'Kano', 'Ibadan'],
        qid: 'ge_abuja'),
    _mcq('Which flag is green-white-green?', 'Nigeria', ['Ghana', 'Kenya', 'Egypt'],
        qid: 'ge_flag_ng'),
    _mcq('Egypt is famous for…', 'Pyramids', ['Ice hotels', 'Rainforests only', 'Volcanoes only'],
        qid: 'ge_egypt'),
    _mcq('The longest river in Africa is the…', 'Nile', ['Niger', 'Congo', 'Zambezi'],
        qid: 'ge_nile'),
    _mcq('Paris is the capital of…', 'France', ['Spain', 'Italy', 'Germany'],
        qid: 'ge_paris'),
    _mcq('London is in…', 'England', ['Brazil', 'Japan', 'Egypt'],
        qid: 'ge_london'),
    _mcq('A globe shows the whole…', 'Earth', ['Moon only', 'School', 'Ocean only'],
        qid: 'ge_globe'),
    _mcq('A map helps you…', 'Find places', ['Cook food', 'Sing songs', 'Sleep'],
        qid: 'ge_map'),
    _mcq('The Sahara is a huge…', 'Desert', ['Ocean', 'Forest', 'City'],
        qid: 'ge_sahara'),
    _mcq('Mountains are…', 'Very high land',
        ['Flat farms', 'Deep oceans', 'Clouds'],
        qid: 'ge_mtn'),
    _mcq('An island is land with water…', 'All around',
        ['Only on one side', 'Underground', 'In space'],
        qid: 'ge_island'),
    _mcq('Oceans are…', 'Big salt water',
        ['Small ponds', 'Dry sand', 'Ice only'],
        qid: 'ge_ocean'),
    _mcq('Africa is a…', 'Continent', ['City', 'River', 'Mountain'],
        qid: 'ge_africa'),
    _mcq('Asia is a…', 'Continent', ['Flag', 'Beach', 'School'],
        qid: 'ge_asia'),
    _mcq('The Equator is an imaginary…', 'Line around Earth',
        ['Mountain', 'Desert', 'Flag'],
        qid: 'ge_eq'),
    _mcq('Kenya is in…', 'Africa', ['Europe', 'Australia', 'Antarctica'],
        qid: 'ge_kenya'),
    _mcq('Brazil is in…', 'South America', ['Africa', 'Europe', 'Asia'],
        qid: 'ge_brazil'),
    _mcq('China is in…', 'Asia', ['Africa', 'Europe', 'Australia'],
        qid: 'ge_china'),
    _mcq('A capital city is where a country\'s…', 'Government sits',
        ['Tallest tree grows', 'Ocean starts', 'Desert ends'],
        qid: 'ge_gov'),
    _mcq('The Statue of Liberty is in…', 'USA',
        ['Nigeria', 'Japan', 'Egypt'],
        qid: 'ge_liberty'),
    _mcq('The Eiffel Tower is in…', 'France',
        ['Italy', 'Spain', 'Ghana'],
        qid: 'ge_eiffel'),
    _mcq('Lagos is a big city in…', 'Nigeria',
        ['France', 'Japan', 'Canada'],
        qid: 'ge_lagos'),
    _mcq('Ghana\'s capital is…', 'Accra', ['Abuja', 'Cairo', 'Nairobi'],
        qid: 'ge_accra'),
    _mcq('Kenya\'s capital is…', 'Nairobi', ['Accra', 'Abuja', 'Cairo'],
        qid: 'ge_nairobi'),
    _mcq('Egypt\'s capital is…', 'Cairo', ['Accra', 'Lagos', 'Pretoria'],
        qid: 'ge_cairo'),
    _mcq('Which direction is opposite of North?', 'South', ['East', 'West', 'Up'],
        qid: 'ge_south'),
    _mcq('Which direction is opposite of East?', 'West', ['North', 'South', 'Down'],
        qid: 'ge_west'),
    _mcq('A compass helps you find…', 'Direction', ['Recipes', 'Songs', 'Colors'],
        qid: 'ge_compass'),
    _mcq('Blue on many maps means…', 'Water', ['Mountains', 'Deserts', 'Cities'],
        qid: 'ge_blue'),
    _mcq('Green on many maps often means…', 'Land / forests', ['Oceans', 'Space', 'Ice only'],
        qid: 'ge_green'),
    _mcq('Australia is both a country and a…', 'Continent', ['Moon', 'River', 'Desert only'],
        qid: 'ge_aus'),
    _mcq('Antarctica is very…', 'Cold', ['Hot', 'Tropical', 'Desert dry hot'],
        qid: 'ge_ant'),
    _mcq('A landmark is a famous…', 'Place', ['Snack', 'Toy', 'Song'],
        qid: 'ge_land'),
    _mcq('The Great Wall is in…', 'China', ['Nigeria', 'Brazil', 'Canada'],
        qid: 'ge_wall'),
    _mcq('Tokyo is the capital of…', 'Japan', ['China', 'Korea myth', 'India'],
        qid: 'ge_tokyo'),
    _mcq('India\'s capital is…', 'New Delhi', ['Mumbai', 'Tokyo', 'Beijing'],
        qid: 'ge_delhi'),
    _mcq('Canada is north of the…', 'USA', ['Brazil', 'Australia', 'Nigeria'],
        qid: 'ge_canada'),
    _mcq('Which is a country in West Africa?', 'Ghana', ['Japan', 'France', 'Chile'],
        qid: 'ge_wa'),
    _mcq('Which ocean touches West Africa?', 'Atlantic', ['Pacific only', 'Arctic only', 'Indian only'],
        qid: 'ge_atl'),
    _mcq('A border separates two…', 'Countries', ['Clouds', 'Stars', 'Songs'],
        qid: 'ge_border'),
    _mcq('Drag countries (quiz): Nigeria is in…', 'Africa', ['Europe', 'Asia', 'Australia'],
        qid: 'ge_ng_cont'),
    _mcq('Match flags quiz: USA flag has…', 'Stars & stripes', ['Only green', 'Only yellow', 'No colors'],
        qid: 'ge_usa'),
    _mcq('Discover landmarks: Table Mountain is near…', 'Cape Town', ['Cairo', 'Lagos', 'Accra'],
        qid: 'ge_table'),
    _mcq('Globe adventure: Earth is shaped like a…', 'Sphere', ['Cube', 'Pyramid', 'Star'],
        qid: 'ge_sphere'),
    _mcq('Which is a capital?', 'Abuja', ['Sahara', 'Nile', 'Atlantic'],
        qid: 'ge_cap'),
    _mcq('Which is NOT a continent?', 'Pacific', ['Africa', 'Asia', 'Europe'],
        qid: 'ge_not'),
    _mcq('Rivers flow into…', 'Seas / oceans', ['The Moon', 'Space', 'Flags'],
        qid: 'ge_river'),
    _mcq('A peninsula is land almost…', 'Surrounded by water', ['Made of ice only', 'Underground', 'In clouds'],
        qid: 'ge_pen'),
    _mcq('Which country is famous for kangaroos?', 'Australia', ['Nigeria', 'Egypt', 'France'],
        qid: 'ge_roo'),
    _mcq('Learn capitals: Spain\'s capital is…', 'Madrid', ['Rome', 'Paris', 'Berlin'],
        qid: 'ge_madrid'),
  ]);
}

List<GameQuestion> buildCodingForKids() {
  return _ensureFifty([
    _mcq('A program is a set of…', 'Instructions', ['Cookies', 'Colors only', 'Songs only'],
        qid: 'code_prog'),
    _mcq('An algorithm is a…', 'Step-by-step plan', ['Random mess', 'Animal', 'Toy'],
        qid: 'code_algo'),
    _mcq('What should come first: put on socks, then shoes?', 'Socks first', ['Shoes first', 'Neither', 'Both same time'],
        qid: 'code_order1'),
    _mcq('Robot maze: go forward TWICE. How many steps?', '2', ['1', '3', '0'],
        qid: 'code_steps'),
    _mcq('If "repeat 3 times: clap", how many claps?', '3', ['1', '2', '4'],
        qid: 'code_loop'),
    _mcq('A bug in coding means a…', 'Mistake', ['Insect toy only', 'Feature', 'Color'],
        qid: 'code_bug'),
    _mcq('Debugging means…', 'Fixing mistakes', ['Making mess', 'Deleting all', 'Sleeping'],
        qid: 'code_debug'),
    _mcq('Drag-and-drop blocks are used to…', 'Build programs', ['Cook soup', 'Plant trees', 'Paint walls'],
        qid: 'code_blocks'),
    _mcq('Logic: If raining → take umbrella. It is raining. What do you do?', 'Take umbrella', ['Swim', 'Fly', 'Ignore'],
        qid: 'code_if'),
    _mcq('True or false in code are…', 'Booleans', ['Fruits', 'Animals', 'Shapes'],
        qid: 'code_bool'),
    _mcq('A loop repeats…', 'Actions', ['Once only forever silence', 'Nothing', 'Food'],
        qid: 'code_loop2'),
    _mcq('Robot faces right, then turns left. Now it faces…', 'Forward again', ['Backwards always', 'Up', 'Down'],
        qid: 'code_turn'),
    _mcq('Sequence: wake up → brush teeth → eat. What is 2nd?', 'Brush teeth', ['Eat', 'Wake up', 'Sleep'],
        qid: 'code_seq'),
    _mcq('To escape a maze, a robot needs a…', 'Clear path plan', ['Random dance only', 'Loud music', 'Candy'],
        qid: 'code_maze'),
    _mcq('Input is what you…', 'Give the computer', ['Only hide', 'Only delete', 'Ignore'],
        qid: 'code_input'),
    _mcq('Output is what the computer…', 'Shows or says', ['Eats', 'Hides forever', 'Forgets'],
        qid: 'code_output'),
    _mcq('Which is a good first coding step?', 'Plan the steps', ['Guess randomly', 'Quit', 'Break device'],
        qid: 'code_plan'),
    _mcq('Puzzle: 1,2,3,4,? What next?', '5', ['7', '9', '0'],
        qid: 'code_pat1'),
    _mcq('Puzzle: 2,4,6,8,? What next?', '10', ['9', '11', '7'],
        qid: 'code_pat2'),
    _mcq('Puzzle: A,B,C,? What next?', 'D', ['Z', 'F', 'X'],
        qid: 'code_pat3'),
    _mcq('If block says "move forward", robot…', 'Goes ahead', ['Sits', 'Sleeps', 'Disappears'],
        qid: 'code_move'),
    _mcq('Nested steps mean steps…', 'Inside other steps', ['Outside Earth', 'In water', 'Invisible'],
        qid: 'code_nest'),
    _mcq('Condition "if hungry" checks…', 'Whether hungry', ['The weather only', 'Your shoes', 'The Moon'],
        qid: 'code_cond'),
    _mcq('Event: when button pressed → jump. Press button, robot…', 'Jumps', ['Sleeps', 'Eats', 'Stops forever'],
        qid: 'code_event'),
    _mcq('Which order opens a door: unlock then open?', 'Unlock first', ['Open first', 'Kick first', 'Paint first'],
        qid: 'code_door'),
    _mcq('Variables store…', 'Information', ['Only magnets', 'Only mud', 'Only clouds'],
        qid: 'code_var'),
    _mcq('Robot wall ahead. Best action?', 'Turn', ['Crash', 'Ignore sensors', 'Close eyes'],
        qid: 'code_wall'),
    _mcq('Repeat until home means…', 'Keep going till home', ['Stop forever', 'Never start', 'Dance once'],
        qid: 'code_until'),
    _mcq('Sorting toys by color is like…', 'Organizing data', ['Erasing Earth', 'Flying', 'Cooking only'],
        qid: 'code_sort'),
    _mcq('A flowchart shows…', 'Steps in order', ['Only pictures of food', 'Random noise', 'Weather only'],
        qid: 'code_flow'),
    _mcq('Which is safer online?', 'Ask a parent', ['Share password', 'Talk to strangers', 'Click all links'],
        qid: 'code_safe'),
    _mcq('Binary often uses digits…', '0 and 1', ['2 and 3', 'A and Z', '5 and 9'],
        qid: 'code_bin'),
    _mcq('Sprite in kids coding is often a…', 'Character on screen', ['Real insect', 'Cloud', 'Mountain'],
        qid: 'code_sprite'),
    _mcq('To make a character walk, you usually…', 'Add move blocks', ['Delete all code', 'Close app', 'Remove screen'],
        qid: 'code_walk'),
    _mcq('Test your code means…', 'Try it out', ['Throw it away', 'Hide it', 'Never run it'],
        qid: 'code_test'),
    _mcq('Logic puzzle: all birds fly. A robin is a bird. So a robin…', 'Flies', ['Swims only', 'Is a fish', 'Is a rock'],
        qid: 'code_logic'),
    _mcq('Maze tip: look ahead before…', 'Moving', ['Eating the map', 'Deleting path', 'Closing eyes'],
        qid: 'code_tip'),
    _mcq('Instructions should be…', 'Clear', ['Confusing', 'Hidden', 'Random'],
        qid: 'code_clear'),
    _mcq('If forever loop with no stop…', 'It keeps going', ['Runs once', 'Never starts', 'Deletes itself'],
        qid: 'code_forever'),
    _mcq('Robot battery low. Best first step?', 'Charge / rest', ['Run maze harder', 'Ignore', 'Throw robot'],
        qid: 'code_bat'),
    _mcq('Which helps solving puzzles?', 'Breaking into steps', ['Panicking', 'Guessing forever', 'Closing book'],
        qid: 'code_break'),
    _mcq('Keyboard & mouse are…', 'Input tools', ['Output only', 'Robots', 'Mazes'],
        qid: 'code_hw'),
    _mcq('Speaker / screen show…', 'Output', ['Only input', 'Only magnets', 'Only soil'],
        qid: 'code_out2'),
    _mcq('Pattern: red, blue, red, blue,? ', 'Red', ['Green', 'Yellow', 'Black'],
        qid: 'code_pat4'),
    _mcq('Count loop from 1 to 4 visits…', '4 times', ['1 time', '2 times', '0 times'],
        qid: 'code_count'),
    _mcq('To avoid maze dead-ends, try…', 'Planning path', ['Running blind', 'Deleting map', 'Shouting'],
        qid: 'code_plan2'),
    _mcq('Code that works correctly is…', 'Successful', ['Broken', 'Useless', 'Invisible'],
        qid: 'code_ok'),
    _mcq('Kids coding teaches…', 'Thinking in steps', ['Only jumping', 'Only singing', 'Only sleeping'],
        qid: 'code_think'),
    _mcq('Turn right twice from north faces…', 'South', ['East', 'West', 'North'],
        qid: 'code_turn2'),
    _mcq('Best team code tip?', 'Share ideas kindly', ['Hide code meanly', 'Break others work', 'Quit'],
        qid: 'code_team'),
  ]);
}

List<GameQuestion> buildArtStudioQuiz() {
  return _ensureFifty([
    ...buildShapesColors().take(25),
    _mcq('Pattern: ● ● ○ ● ● ○ ● ● ?', '○', ['●', '△', '■'], qid: 'art_pat1'),
    _mcq('Pattern: ▲ ■ ▲ ■ ▲ ?', '■', ['▲', '●', '★'], qid: 'art_pat2'),
    _mcq('Complete: red, orange, yellow, ?', 'Green', ['Black', 'White', 'Gray'],
        qid: 'art_rain'),
    _mcq('A coloring page is for…', 'Coloring', ['Eating', 'Burning', 'Hiding'],
        qid: 'art_color'),
    _mcq('Drawing uses lines and…', 'Shapes', ['Only silence', 'Only numbers', 'Only sleep'],
        qid: 'art_draw'),
    _mcq('Primary colors include…', 'Red', ['Brown', 'Pink', 'Gray'],
        qid: 'art_pri'),
    _mcq('Stickers are fun…', 'Collections', ['Meals', 'Rivers', 'Storms'],
        qid: 'art_stick'),
    _mcq('A circle has…', 'No corners', ['4 corners', '3 corners', '5 corners'],
        qid: 'art_circ'),
    _mcq('Mixing paint carefully makes…', 'New colors', ['Noise', 'Rain', 'Ice'],
        qid: 'art_mix'),
    _mcq('Pattern: 1 star, 2 hearts, 1 star, 2 hearts, 1 star, ?', '2 hearts',
        ['3 stars', '1 heart', '4 circles'],
        qid: 'art_pat3'),
    _mcq('An artist creates…', 'Art', ['Only exams', 'Only roads', 'Only clouds'],
        qid: 'art_artist'),
    _mcq('Which is a drawing tool?', 'Pencil', ['Spoon', 'Sock', 'Leaf only'],
        qid: 'art_tool'),
    _mcq('Symmetry means sides look…', 'The same', ['Random', 'Broken', 'Invisible'],
        qid: 'art_sym'),
    _mcq('Complete shape: square needs…', '4 equal sides', ['3 sides', '0 sides', '1 side'],
        qid: 'art_sq'),
    _mcq('Warm color example?', 'Orange', ['Ice blue only', 'Gray only', 'Black only'],
        qid: 'art_warm'),
    _mcq('Cool color example?', 'Blue', ['Fire red only', 'Sun yellow only', 'Lava orange'],
        qid: 'art_cool'),
    _mcq('Pattern ABAB next after A B A is…', 'B', ['A', 'C', 'Z'],
        qid: 'art_abab'),
    _mcq('Sticker challenge: collect by…', 'Theme / color', ['Throwing away', 'Eating', 'Hiding forever'],
        qid: 'art_collect'),
    _mcq('Shape creation: 3 sides make a…', 'Triangle', ['Circle', 'Oval', 'Sphere'],
        qid: 'art_tri'),
    _mcq('Coloring inside lines shows…', 'Care', ['Rush only', 'Noise', 'Sleep'],
        qid: 'art_care'),
    _mcq('Canvas is a place to…', 'Draw / paint', ['Sleep only', 'Cook', 'Swim'],
        qid: 'art_canvas'),
    _mcq('Outline is the…', 'Outer line', ['Middle color only', 'Sound', 'Smell'],
        qid: 'art_out'),
    _mcq('Pattern ★ ★ ☆ ★ ★ ☆ ★ ★ ?', '☆', ['★', '●', '■'], qid: 'art_pat4'),
    _mcq('Texture means how something…', 'Feels', ['Tastes only', 'Sings', 'Flies'],
        qid: 'art_tex'),
    _mcq('Collage uses many…', 'Pieces together', ['Only one color forever', 'Only sound', 'Only code'],
        qid: 'art_col'),
  ]);
}

List<GameQuestion> buildMusicAcademy() {
  return _ensureFifty([
    _mcq('A piano has…', 'Keys', ['Wheels', 'Wings', 'Roots'], qid: 'mus_keys'),
    _mcq('Do Re Mi are…', 'Musical notes', ['Colors', 'Animals', 'Countries'],
        qid: 'mus_notes'),
    _mcq('Rhythm is the…', 'Beat / pattern in time', ['Color of paint', 'Taste of soup', 'Smell of rain'],
        qid: 'mus_rhythm'),
    _mcq('A drum is mostly for…', 'Rhythm', ['Reading only', 'Cooking', 'Flying'],
        qid: 'mus_drum'),
    _mcq('A guitar has…', 'Strings', ['Wheels', 'Petals', 'Screens'],
        qid: 'mus_guitar'),
    _mcq('A flute is a…', 'Wind instrument', ['Drum only', 'String only', 'Rock'],
        qid: 'mus_flute'),
    _mcq('Singing uses your…', 'Voice', ['Elbows only', 'Shoes', 'Hair'],
        qid: 'mus_sing'),
    _mcq('Loud and soft are about…', 'Volume', ['Color', 'Smell', 'Weight'],
        qid: 'mus_vol'),
    _mcq('Fast and slow are about…', 'Tempo', ['Taste', 'Height', 'Shadow'],
        qid: 'mus_tempo'),
    _mcq('A violin is played with a…', 'Bow', ['Hammer', 'Spoon', 'Brush only'],
        qid: 'mus_violin'),
    _mcq('Clapping can match…', 'Rhythm', ['Gravity', 'Weather only', 'Math only'],
        qid: 'mus_clap'),
    _mcq('Which instrument has black and white keys?', 'Piano', ['Drum', 'Flute', 'Tambourine'],
        qid: 'mus_piano'),
    _mcq('A song has…', 'Melody', ['Only silence', 'Only dirt', 'Only sand'],
        qid: 'mus_mel'),
    _mcq('Orchestra is a…', 'Group of musicians', ['Single drum', 'Toy car', 'Planet'],
        qid: 'mus_orch'),
    _mcq('High and low sounds are…', 'Pitch', ['Weight', 'Length', 'Smell'],
        qid: 'mus_pitch'),
    _mcq('A xylophone is hit with…', 'Mallets', ['Socks', 'Leaves', 'Clouds'],
        qid: 'mus_xylo'),
    _mcq('Trumpet is a…', 'Brass instrument', ['String only', 'Drum only', 'Plant'],
        qid: 'mus_trump'),
    _mcq('Counting 1-2-3-4 helps with…', 'Rhythm', ['Cooking rice only', 'Sleeping only', 'Painting only'],
        qid: 'mus_count'),
    _mcq('If the beat is clap-clap-rest, how many claps?', '2', ['1', '3', '4'],
        qid: 'mus_beat'),
    _mcq('Music notes are written on a…', 'Staff', ['Road', 'River', 'Desert'],
        qid: 'mus_staff'),
    _mcq('Choir means people…', 'Sing together', ['Swim together', 'Sleep together', 'Hide alone'],
        qid: 'mus_choir'),
    _mcq('A rest in music means…', 'Silence', ['Louder sound', 'Faster notes', 'New color'],
        qid: 'mus_rest'),
    _mcq('Instrument recognition: which has strings?', 'Guitar', ['Flute', 'Drum', 'Triangle'],
        qid: 'mus_rec1'),
    _mcq('Instrument recognition: which you blow?', 'Flute', ['Violin', 'Guitar', 'Piano'],
        qid: 'mus_rec2'),
    _mcq('Instrument recognition: which you hit?', 'Drum', ['Flute', 'Violin', 'Recorder'],
        qid: 'mus_rec3'),
    _mcq('Piano mini-game: middle C is a…', 'Note', ['Fruit', 'Country', 'Animal'],
        qid: 'mus_c'),
    _mcq('Matching rhythm: clap when you hear the…', 'Beat', ['Color', 'Smell', 'Shadow'],
        qid: 'mus_match'),
    _mcq('A melody is a…', 'Tune', ['Mountain', 'Cloud', 'Shoe'], qid: 'mus_tune'),
    _mcq('Headphones help you…', 'Listen', ['Plant', 'Cook', 'Dig'],
        qid: 'mus_head'),
    _mcq('Dancing often follows the…', 'Beat', ['Silent rocks', 'Invisible ink', 'Mud only'],
        qid: 'mus_dance'),
    _mcq('Which is highest pitch roughly?', 'Bird tweet', ['Thunder boom', 'Bass drum', 'Elephant stomp'],
        qid: 'mus_high'),
    _mcq('Which is lower pitch roughly?', 'Big drum', ['Tiny whistle', 'Bird chirp', 'Mosquito buzz'],
        qid: 'mus_low'),
    _mcq('Music academy reward for practice is…', 'Getting better', ['Getting worse', 'Losing notes', 'Breaking drums'],
        qid: 'mus_practice'),
    _mcq('A metronome keeps…', 'Steady time', ['Random time', 'No time', 'Only color'],
        qid: 'mus_metro'),
    _mcq('Harmony is when notes…', 'Sound good together', ['Fight', 'Disappear', 'Turn into food'],
        qid: 'mus_harm'),
    _mcq('Recorder is often learned…', 'In school music', ['Only underwater', 'Only in caves', 'Only in space'],
        qid: 'mus_rec'),
    _mcq('Cymbals make a…', 'Crash sound', ['Whisper only', 'Silent beam', 'Smell'],
        qid: 'mus_cym'),
    _mcq('Tambourine you often…', 'Shake / tap', ['Blow hard', 'Plug in', 'Plant'],
        qid: 'mus_tam'),
    _mcq('Scale Do-Re-Mi climbs…', 'Up in pitch', ['Down into mud', 'Sideways only', 'Into space silence'],
        qid: 'mus_scale'),
    _mcq('Soft music is…', 'Quiet', ['Always loud', 'Always fast', 'Always angry'],
        qid: 'mus_soft'),
    _mcq('A duet means…', 'Two performers', ['Ten orchestras', 'Zero people', 'One silent statue'],
        qid: 'mus_duet'),
    _mcq('Encore means…', 'Play again', ['Stop forever', 'Leave stage immediately forever', 'Break instruments'],
        qid: 'mus_encore'),
    _mcq('Listening carefully helps…', 'Recognize instruments', ['Ignore music', 'Break rhythm', 'Lose beat'],
        qid: 'mus_listen'),
    _mcq('Beat matching game: clap on 1 and 3 — claps per 4 counts?', '2', ['1', '3', '4'],
        qid: 'mus_13'),
    _mcq('Music can express…', 'Feelings', ['Only math homework', 'Only weather reports', 'Only maps'],
        qid: 'mus_feel'),
    _mcq('Which family is trumpet?', 'Brass', ['Strings', 'Percussion only', 'Woodwind only'],
        qid: 'mus_brass'),
    _mcq('Which family is violin?', 'Strings', ['Brass', 'Percussion', 'Keyboard only'],
        qid: 'mus_str'),
    _mcq('Which family is snare drum?', 'Percussion', ['Brass', 'Strings', 'Woodwind'],
        qid: 'mus_perc'),
    _mcq('Learning notes helps you…', 'Read music', ['Cook faster', 'Dig deeper', 'Sleep louder'],
        qid: 'mus_read'),
    _mcq('Fun music tip: practice a little…', 'Every day', ['Never', 'Only once a year', 'While sleeping only'],
        qid: 'mus_daily'),
  ]);
}

List<GameQuestion> buildMemoryChallengeQuiz() {
  // Sequence memory via MCQ (pairs with flip-card custom screen too).
  final qs = <GameQuestion>[];
  final seqs = [
    (['🍎', '🍌', '🍇'], '🍎 → 🍌 → ?', '🍇', ['🍊', '🍉', '🥝']),
    (['1', '2', '3'], '1 → 2 → ?', '3', ['4', '5', '0']),
    (['A', 'B', 'C'], 'A → B → ?', 'C', ['D', 'E', 'Z']),
    (['🔴', '🔵', '🔴'], '🔴 → 🔵 → ?', '🔴', ['🔵', '🟢', '🟡']),
    (['🐶', '🐱', '🐶'], '🐶 → 🐱 → ?', '🐶', ['🐭', '🐰', '🦊']),
    (['▲', '■', '▲'], '▲ → ■ → ?', '▲', ['■', '●', '★']),
    (['2', '4', '6'], '2 → 4 → ?', '6', ['5', '7', '8']),
    (['Do', 'Re', 'Mi'], 'Do → Re → ?', 'Mi', ['Fa', 'Sol', 'La']),
  ];
  for (var i = 0; i < seqs.length; i++) {
    final s = seqs[i];
    qs.add(_mcq('Remember the sequence!\n${s.$2}', s.$3, s.$4, qid: 'mem_seq_$i'));
  }
  for (var i = 0; i < 42; i++) {
    final a = kidGameRand.nextInt(9) + 1;
    final b = kidGameRand.nextInt(9) + 1;
    final c = kidGameRand.nextInt(9) + 1;
    qs.add(_mcq(
      'Memory flash!\nYou saw: $a · $b · $c\nWhat was the MIDDLE number?',
      '$b',
      _numDistractors(b),
      qid: 'mem_mid_${i}_$b',
    ));
  }
  return _ensureFifty(qs);
}

List<GameQuestion> buildPuzzleWorld() {
  return _ensureFifty([
    _mcq('Jigsaw tip: start with the…', 'Edges / corners', ['Middle only forever', 'Random throwing', 'Eating pieces'],
        qid: 'pz_edge'),
    _mcq('Shape match: □ matches…', 'Square', ['Circle', 'Triangle', 'Oval'],
        qid: 'pz_sq'),
    _mcq('Shape match: △ matches…', 'Triangle', ['Square', 'Circle', 'Hexagon'],
        qid: 'pz_tri'),
    _mcq('Shape match: ○ matches…', 'Circle', ['Square', 'Triangle', 'Star'],
        qid: 'pz_cir'),
    _mcq('Pattern: ⭐⭐🌙⭐⭐🌙⭐⭐?', '🌙', ['⭐', '☀️', '☁️'], qid: 'pz_pat1'),
    _mcq('Logic: All squares have 4 sides. This shape has 4 equal sides. It may be a…', 'Square', ['Circle', 'Oval', 'Sphere'],
        qid: 'pz_logic'),
    _mcq('Which piece fits a round hole?', 'Round peg', ['Square peg', 'Triangle peg', 'Star peg'],
        qid: 'pz_fit'),
    _mcq('Odd one out: 🐶 🐱 🐭 🚗', '🚗', ['🐶', '🐱', '🐭'], qid: 'pz_odd1'),
    _mcq('Odd one out: 🍎 🍌 🚗 🍇', '🚗', ['🍎', '🍌', '🍇'], qid: 'pz_odd2'),
    _mcq('Complete: 2, 4, 6, ?', '8', ['7', '9', '5'], qid: 'pz_num'),
    _mcq('Complete: A C E ?', 'G', ['B', 'D', 'F'], qid: 'pz_let'),
    _mcq('Puzzle: big is to small as tall is to…', 'Short', ['Wide', 'Long', 'High'],
        qid: 'pz_ana'),
    _mcq('If left is opposite right, up is opposite…', 'Down', ['Left', 'Right', 'Side'],
        qid: 'pz_opp'),
    _mcq('Sorting: put small → medium → …', 'Large', ['Tiny', 'Invisible', 'Gone'],
        qid: 'pz_sort'),
    _mcq('Matching pairs need…', 'Same things', ['Opposite things only', 'Random cards', 'Broken sets'],
        qid: 'pz_pair'),
    _mcq('A maze exit is found by…', 'Following open paths', ['Closing eyes', 'Eating the map', 'Deleting walls'],
        qid: 'pz_maze'),
    _mcq('Pattern recognition: ABA B? next letter style → ABA', 'B', ['A', 'C', 'Z'],
        qid: 'pz_aba'),
    _mcq('Tangram pieces make…', 'Pictures / shapes', ['Only noise', 'Only rain', 'Only food'],
        qid: 'pz_tan'),
    _mcq('Logic: If only red blocks are here, pick…', 'Red', ['Blue', 'Green', 'Yellow'],
        qid: 'pz_color'),
    _mcq('Which continues: ◆◇◆◇◆?', '◇', ['◆', '●', '▲'], qid: 'pz_dia'),
    _mcq('Puzzle world trophy for…', 'Solving puzzles', ['Giving up', 'Breaking pieces', 'Hiding board'],
        qid: 'pz_trophy'),
    _mcq('Corners of a rectangle: how many?', '4', ['3', '5', '6'], qid: 'pz_corner'),
    _mcq('Sudoku for kids starts with…', 'Logic & numbers', ['Only painting', 'Only dancing', 'Only cooking'],
        qid: 'pz_sudo'),
    _mcq('Missing piece of sky is often…', 'Blue / cloud piece', ['Shoe piece', 'Soup piece', 'Sock piece'],
        qid: 'pz_sky'),
    _mcq('Group animals with…', 'Similar traits', ['Random unrelated items', 'Cars only', 'Tools only'],
        qid: 'pz_group'),
    _mcq('Rotate a triangle — sides stay…', '3', ['2', '4', '5'], qid: 'pz_rot'),
    _mcq('Mirror of left hand looks like…', 'Right hand shape', ['A foot', 'A circle', 'A star'],
        qid: 'pz_mir'),
    _mcq('Which is a pattern?', 'Repeating order', ['One random splash', 'Silence forever', 'Nothing'],
        qid: 'pz_def'),
    _mcq('Complete story order: begin → middle → …', 'End', ['Begin again only', 'Nothing', 'Middle forever'],
        qid: 'pz_story'),
    _mcq('Balance scale: 2 = 2 means…', 'Equal', ['Heavier left', 'Heavier right', 'Broken'],
        qid: 'pz_bal'),
    _mcq('Find twin: 🔶 matches…', '🔶', ['🔷', '🔺', '⚫'], qid: 'pz_twin'),
    _mcq('Hard puzzle tip: try…', 'Calm steps', ['Rush forever', 'Quit instantly', 'Throw puzzle'],
        qid: 'pz_tip'),
    _mcq('Logic gate for kids: yes → go, no → stop. No means…', 'Stop', ['Go', 'Dance', 'Fly'],
        qid: 'pz_gate'),
    _mcq('Which number is missing: 1 2 _ 4 5?', '3', ['6', '7', '0'], qid: 'pz_miss'),
    _mcq('Cube has how many faces?', '6', ['4', '5', '8'], qid: 'pz_cube'),
    _mcq('Shadow puzzle depends on…', 'Light direction', ['Smell', 'Taste', 'Sound only'],
        qid: 'pz_shad'),
    _mcq('Riddle: what has hands but can’t clap? (kids)', 'Clock', ['Person', 'Dog', 'Fish'],
        qid: 'pz_rid'),
    _mcq('Connect dots in…', 'Number order', ['Random chaos only', 'Color only forever', 'Smell order'],
        qid: 'pz_dots'),
    _mcq('Tile match: same picture =…', 'Pair', ['Lose', 'Skip', 'Delete'],
        qid: 'pz_tile'),
    _mcq('Escape room kid tip: read…', 'Clues carefully', ['Nothing', 'Only the floor', 'Only the sky'],
        qid: 'pz_clue'),
    _mcq('Which puzzle trains focus?', 'Jigsaw', ['Ignoring all', 'Sleeping mid-game', 'Throwing pieces'],
        qid: 'pz_focus'),
    _mcq('Sequence: morning → afternoon → …', 'Evening', ['Morning again instantly', 'Yesterday only', 'Never'],
        qid: 'pz_day'),
    _mcq('Classify: spoon, fork, knife are…', 'Utensils', ['Animals', 'Planets', 'Letters'],
        qid: 'pz_class'),
    _mcq('Next shape after 2 circles & 1 square repeating: ○○□○○□○○?', '□', ['○', '△', '★'],
        qid: 'pz_rep'),
    _mcq('Brain break: stretch then…', 'Continue calmly', ['Break screen', 'Throw tablet', 'Yell'],
        qid: 'pz_break'),
    _mcq('Winning puzzles feels like…', 'Achievement', ['Failure', 'Sleepiness only', 'Anger only'],
        qid: 'pz_win'),
    _mcq('Spatial puzzle asks where things…', 'Fit / sit', ['Taste', 'Smell', 'Sing'],
        qid: 'pz_space'),
    _mcq('Code puzzle letters: C A T means…', 'Cat', ['Dog', 'Car', 'Cup'],
        qid: 'pz_cat'),
    _mcq('Finish the set: red triangle, blue triangle, ? triangle', 'Any color triangle', ['Only a circle', 'Only a car', 'Only a drum'],
        qid: 'pz_set'),
    _mcq('Puzzle World motto?', 'Think & try', ['Never try', 'Only guess forever wrong', 'Quit always'],
        qid: 'pz_motto'),
  ]);
}

List<GameQuestion> buildQuizBattle() {
  final mix = <GameQuestion>[
    ...buildFunQuiz().take(20),
    ...buildMathChallenge().take(10),
    ...buildScienceFacts().take(10),
    ...buildGeography().take(10),
  ];
  mix.shuffle(kidGameRand);
  // Re-id to avoid seen-key collisions with source banks
  return mix.take(50).toList().asMap().entries.map((e) {
    final q = e.value;
    return GameQuestion(
      prompt: '⚡ Quiz Battle!\n${q.prompt}',
      options: q.options,
      correct: q.correct,
      speakWord: q.speakWord,
      qid: 'qb_${e.key}_${q.id}',
    );
  }).toList();
}

List<GameQuestion> buildTreasureHunt() {
  final qs = <GameQuestion>[];
  final challenges = [
    ('Unlock the chest: 2 + 3 = ?', '5', ['4', '6', '7'], 'chest'),
    ('Open the map: capital of Nigeria?', 'Abuja', ['Lagos', 'Kano', 'Ibadan'], 'map'),
    ('Earn a badge: 4 × 2 = ?', '8', ['6', '7', '9'], 'badge'),
    ('Coin reward: opposite of hot?', 'Cold', ['Warm', 'Fire', 'Sun'], 'coin'),
    ('Surprise vault: letter after B?', 'C', ['A', 'D', 'E'], 'surprise'),
    ('Treasure gate: how many sides on a triangle?', '3', ['4', '5', '2'], 'gate'),
    ('Chest code: planet we live on?', 'Earth', ['Mars', 'Venus', 'Moon'], 'earth'),
    ('Map piece: fish live in…', 'Water', ['Fire', 'Sky nests', 'Deserts only'], 'fish'),
    ('Badge quiz: we see with our…', 'Eyes', ['Ears', 'Nose', 'Hair'], 'eyes'),
    ('Coin puzzle: 10 − 4 = ?', '6', ['5', '7', '8'], 'sub'),
  ];
  for (var i = 0; i < challenges.length; i++) {
    final c = challenges[i];
    qs.add(_mcq(
      '🏴‍☠️ Treasure Hunt!\n${c.$1}',
      c.$2,
      c.$3,
      speakWord: c.$2,
      qid: 'th_${c.$4}_$i',
    ));
  }
  for (var i = 0; i < 40; i++) {
    final a = kidGameRand.nextInt(8) + 1;
    final b = kidGameRand.nextInt(8) + 1;
    final sum = a + b;
    qs.add(_mcq(
      'Treasure hunt challenge #$i\nSolve to unlock coins!\n$a + $b = ?',
      '$sum',
      _numDistractors(sum),
      qid: 'th_race_$i',
    ));
  }
  return _ensureFifty(qs);
}

List<GameQuestion> buildVirtualPetQuiz() {
  return _ensureFifty([
    _mcq('Your pet gets happier when you…', 'Finish a lesson', ['Ignore learning', 'Skip forever', 'Close the app always'],
        qid: 'pet_lesson'),
    _mcq('Daily learning helps your pet stay…', 'Happy', ['Angry forever', 'Invisible', 'Gone'],
        qid: 'pet_daily'),
    _mcq('Accessories unlock when you…', 'Progress / level up', ['Quit', 'Never study', 'Break rules'],
        qid: 'pet_acc'),
    _mcq('A virtual pet teaches…', 'Consistent study habits', ['Giving up', 'Cheating', 'Skipping'],
        qid: 'pet_habit'),
    _mcq('Feed knowledge: 1 + 1 = ?', '2', ['1', '3', '0'], qid: 'pet_feed1'),
    _mcq('Pet care: brush teeth helps… YOU stay…', 'Healthy', ['Muddy', 'Sleepy only', 'Hungry only'],
        qid: 'pet_health'),
    _mcq('Pets need kindness. Kindness is…', 'Caring', ['Mean teasing', 'Ignoring forever', 'Hurting'],
        qid: 'pet_kind'),
    _mcq('If pet is sleepy, you should…', 'Let it rest then learn again', ['Scare it', 'Throw it', 'Forget forever'],
        qid: 'pet_rest'),
    _mcq('Level up math: 3 + 2 = ?', '5', ['4', '6', '7'], qid: 'pet_lv1'),
    _mcq('Unlock hat quiz: opposite of sad?', 'Happy', ['Angry', 'Tired', 'Hungry'],
        qid: 'pet_hat'),
    _mcq('Pet grows when lessons are…', 'Completed', ['Ignored', 'Deleted', 'Never started'],
        qid: 'pet_grow'),
    _mcq('Adopt means you…', 'Care for a pet', ['Abandon it', 'Forget it', 'Scare it'],
        qid: 'pet_adopt'),
    _mcq('Study streak keeps pet…', 'Excited', ['Sad forever', 'Lost', 'Broken'],
        qid: 'pet_streak'),
    _mcq('Quiz treat: letter after A?', 'B', ['C', 'Z', 'D'], qid: 'pet_abc'),
    _mcq('Pet accessory: ribbon unlocks after…', 'Progress', ['Cheating', 'Quitting', 'Sleeping only'],
        qid: 'pet_rib'),
    _mcq('Water the plant-pet of learning with…', 'Practice', ['Only screen time junk', 'Only silence', 'Only fear'],
        qid: 'pet_water'),
    _mcq('Happy pet face means…', 'You studied today', ['You never opened lessons', 'You ignored all goals', 'You quit'],
        qid: 'pet_face'),
    _mcq('Math treat: 5 − 2 = ?', '3', ['2', '4', '1'], qid: 'pet_math'),
    _mcq('Pet name tip: choose something…', 'Friendly', ['Mean', 'Scary forever', 'Rude'],
        qid: 'pet_name'),
    _mcq('Encourage habits by playing a little…', 'Each day', ['Never', 'Once in lifetime', 'Only when forced'],
        qid: 'pet_day'),
    ...List.generate(30, (i) {
      final a = (i % 6) + 1;
      final b = (i % 4) + 1;
      return _mcq(
        'Pet snack quiz #$i\n$a + $b = ?',
        '${a + b}',
        _numDistractors(a + b),
        qid: 'pet_snack_$i',
      );
    }),
  ]);
}

List<GameQuestion> buildSchoolCityBuilder() {
  return _ensureFifty([
    _mcq('Earn coins by completing…', 'Lessons', ['Skipping forever', 'Breaking rules', 'Hiding homework'],
        qid: 'city_lessons'),
    _mcq('Finish homework to earn…', 'Coins', ['Dust', 'Trouble only', 'Nothing ever'],
        qid: 'city_hw'),
    _mcq('Passing quizzes helps you…', 'Build your city', ['Destroy learning', 'Lose coins always', 'Quit school'],
        qid: 'city_quiz'),
    _mcq('School City grows when you…', 'Learn & earn', ['Never try', 'Only sleep', 'Only complain'],
        qid: 'city_grow'),
    _mcq('Build a library by answering: books live in a…', 'Library', ['River', 'Oven', 'Cloud'],
        qid: 'city_lib'),
    _mcq('Build a playground: fun place to…', 'Play', ['Sleep in class', 'Fight', 'Hide forever'],
        qid: 'city_play'),
    _mcq('Coin shop math: 4 + 4 = ?', '8', ['7', '9', '6'], qid: 'city_coin1'),
    _mcq('Unlock classroom: teacher helps you…', 'Learn', ['Forget', 'Sleep only', 'Quit'],
        qid: 'city_class'),
    _mcq('City tip: save coins for…', 'New buildings', ['Throwing away', 'Deleting city', 'Breaking maps'],
        qid: 'city_save'),
    _mcq('Homework done = …', 'Progress', ['Zero progress', 'Lost day', 'Broken streak'],
        qid: 'city_done'),
    _mcq('Quiz pass badge unlocks…', 'City upgrades', ['Locks forever', 'Darkness', 'Silence only'],
        qid: 'city_badge'),
    _mcq('Math for builders: 6 − 1 = ?', '5', ['4', '6', '7'], qid: 'city_math'),
    _mcq('A school needs a…', 'Classroom', ['Volcano only', 'Ocean only', 'Desert only'],
        qid: 'city_need'),
    _mcq('Friends in School City should be…', 'Kind', ['Mean', 'Rude', 'Unfair'],
        qid: 'city_kind'),
    _mcq('Earn double coins by…', 'Doing your best', ['Cheating', 'Copying', 'Giving up'],
        qid: 'city_best'),
    ...List.generate(35, (i) {
      final a = (i % 7) + 2;
      final b = (i % 5) + 1;
      return _mcq(
        'City coin challenge #$i\n$a + $b = ?',
        '${a + b}',
        _numDistractors(a + b),
        qid: 'city_earn_$i',
      );
    }),
  ]);
}

// ── helpers (local to adventure banks) ───────────────────────────────────────

GameQuestion _mcq(
  String prompt,
  String correct,
  List<String> distractors, {
  String? speakWord,
  String? qid,
}) {
  final options = <String>[correct, ...distractors]..shuffle(kidGameRand);
  return GameQuestion(
    prompt: prompt,
    options: options,
    correct: options.indexOf(correct),
    speakWord: speakWord,
    qid: qid ?? prompt,
  );
}

List<GameQuestion> _ensureFifty(List<GameQuestion> qs) {
  if (qs.length >= 50) return qs.take(50).toList();
  final out = List<GameQuestion>.from(qs);
  var i = 0;
  while (out.length < 50 && qs.isNotEmpty) {
    final base = qs[i % qs.length];
    out.add(GameQuestion(
      prompt: '${base.prompt} (${out.length + 1})',
      options: base.options,
      correct: base.correct,
      speakWord: base.speakWord,
      qid: '${base.id}_pad_${out.length}',
    ));
    i++;
  }
  return out;
}

List<String> _pick3(List<String> source) {
  final copy = List<String>.from(source)..shuffle(kidGameRand);
  return copy.take(3).toList();
}

List<String> _numDistractors(int correct) {
  final set = <String>{};
  while (set.length < 3) {
    final n = correct + kidGameRand.nextInt(7) - 3;
    if (n != correct && n >= 0) set.add('$n');
  }
  return set.toList();
}
