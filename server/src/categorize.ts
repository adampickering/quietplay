/**
 * Keyword-driven category assignment. Runs when a channel is added so
 * the tvOS "Categories" sidebar section has something to group by. The
 * rules are deliberately overlapping-first-wins: Trains before Cars so
 * "motor rail" lands in Trains, Restoration before Cars so
 * "Baumgartner Restoration" doesn't become a car channel.
 *
 * Output is free text stored in channels.category. The client maps
 * unknown strings (including future additions) to "Other".
 */

export type Category =
  | 'Trains'
  | 'LEGO'
  | 'Restoration'
  | 'Cars'
  | 'Engineering'
  | 'History'
  | 'Kids'
  | 'Other';

interface Rule {
  category: Category;
  keywords: string[];
}

const RULES: Rule[] = [
  {
    category: 'Trains',
    keywords: [
      'train', 'rail', 'loco', 'steam', 'station', 'tug', 'diesel', 'thomas',
      'narrow gauge', 'cadence', 'tram', 'corris', 'talyllyn', 'ffestiniog',
      'terrier', 'hyce', 'coaster', 'paddlewheel', 'choo choo', 'preserved',
      'yankee', 'sprice',
    ],
  },
  {
    category: 'LEGO',
    keywords: [
      'brick', 'lego', 'minifig', 'puzzlego', 'trikbrix', 'rjm',
    ],
  },
  {
    category: 'Restoration',
    keywords: [
      'restoration', 'restored', 'wreck', 'rescue', 'revive', 'refurb',
      'fixit', 'goldsmith', 'baumgartner', 'odd tinkering', 'wreck2',
    ],
  },
  {
    category: 'Cars',
    keywords: [
      'car', 'motor', 'garage', 'truck', 'firebird', 'diecast',
      'matchbox', 'ammo', 'top gear', 'powernation', 'vice grip',
      'jennings',
    ],
  },
  {
    category: 'Engineering',
    keywords: [
      'engineering', 'science', 'practical', 'physics', 'civil',
      'stuff made', 'ridiculous', 'projectair', 'flite', 'ramy', 'engineezy',
      'xkcd', 'what if', 'ship designs', 'primal space', 'dr. engine',
      'dr engine', 'way out west',
    ],
  },
  {
    category: 'History',
    keywords: [
      'museum', 'history', 'historic', 'past', 'british museum',
      'henry ford', 'pinnacle', 'memory', 'oceanliner', 'ultimate restorations',
      'time travel', 'skynea', 'sidequest', 'vintage',
    ],
  },
  {
    category: 'Kids',
    keywords: [
      'paddington', 'yarn', 'kids', 'art for kids', 'animation', 'animat',
      'clock tv', 'andymation', 'hevesh', 'little farm',
    ],
  },
];

export function categorize(title: string | null | undefined): Category {
  if (!title) return 'Other';
  const lower = title.toLowerCase();
  for (const rule of RULES) {
    for (const kw of rule.keywords) {
      if (lower.includes(kw)) return rule.category;
    }
  }
  return 'Other';
}
