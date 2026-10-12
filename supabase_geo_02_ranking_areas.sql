-- ============================================================
-- COACHCARDS: Geographical Ranking System — Phase 1, File 2 of 5
-- Data: ranking_areas — 118 rows (1 national, 4 countries, 113 local)
--
-- Insert order matters: UK → Countries → Local areas (FK dependency)
-- ON CONFLICT DO NOTHING makes this safe to re-run.
--
-- ONS codes included where well-established; NULL where the
-- ceremonial county has no single ONS administrative code
-- (e.g. counties where the council was replaced by UAs).
-- Verify all ONS codes at: https://geoportal.statistics.gov.uk/
--
-- Display_name values for England two-tier counties MUST match
-- what Postcodes.io returns in the admin_county field exactly.
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- National and Country rows
-- ──────────────────────────────────────────────────────────
INSERT INTO ranking_areas (id, area_type, country, display_name, slug, parent_id, ons_code, sort_order)
VALUES
  ('UK',  'national', NULL,               'United Kingdom',    'united-kingdom',     NULL,  'K02000001', 0),
  ('ENG', 'country',  'England',          'England',           'england',            'UK',  'E92000001', 1),
  ('SCO', 'country',  'Scotland',         'Scotland',          'scotland',           'UK',  'S92000003', 2),
  ('WLS', 'country',  'Wales',            'Wales',             'wales',              'UK',  'W92000004', 3),
  ('NIR', 'country',  'Northern Ireland', 'Northern Ireland',  'northern-ireland',   'UK',  'N92000002', 4)
ON CONFLICT (id) DO NOTHING;


-- ──────────────────────────────────────────────────────────
-- England — 48 Ceremonial Counties
-- sort_order is alphabetical (1–48)
-- ons_code: E10xxxxxx for counties with active county council;
--           NULL for ceremonial counties that have no council
--           (all-UA or metropolitan). Verify at ONS portal.
-- ──────────────────────────────────────────────────────────
INSERT INTO ranking_areas (id, area_type, country, display_name, slug, parent_id, ons_code, sort_order)
VALUES
  ('ENG_BEDFORDSHIRE',       'local', 'England', 'Bedfordshire',              'bedfordshire',              'ENG', NULL,         1),
  ('ENG_BERKSHIRE',          'local', 'England', 'Berkshire',                 'berkshire',                 'ENG', NULL,         2),
  ('ENG_BRISTOL',            'local', 'England', 'Bristol',                   'bristol',                   'ENG', NULL,         3),
  ('ENG_BUCKINGHAMSHIRE',    'local', 'England', 'Buckinghamshire',           'buckinghamshire',           'ENG', NULL,         4),
  ('ENG_CAMBRIDGESHIRE',     'local', 'England', 'Cambridgeshire',            'cambridgeshire',            'ENG', 'E10000003',  5),
  ('ENG_CHESHIRE',           'local', 'England', 'Cheshire',                  'cheshire',                  'ENG', NULL,         6),
  ('ENG_CORNWALL',           'local', 'England', 'Cornwall',                  'cornwall',                  'ENG', NULL,         7),
  ('ENG_CUMBRIA',            'local', 'England', 'Cumbria',                   'cumbria',                   'ENG', NULL,         8),
  ('ENG_DERBYSHIRE',         'local', 'England', 'Derbyshire',                'derbyshire',                'ENG', 'E10000007',  9),
  ('ENG_DEVON',              'local', 'England', 'Devon',                     'devon',                     'ENG', 'E10000008', 10),
  ('ENG_DORSET',             'local', 'England', 'Dorset',                    'dorset',                    'ENG', NULL,        11),
  ('ENG_DURHAM',             'local', 'England', 'Durham',                    'durham',                    'ENG', NULL,        12),
  ('ENG_EAST_RIDING',        'local', 'England', 'East Riding of Yorkshire',  'east-riding-of-yorkshire',  'ENG', NULL,        13),
  ('ENG_EAST_SUSSEX',        'local', 'England', 'East Sussex',               'east-sussex',               'ENG', 'E10000011', 14),
  ('ENG_ESSEX',              'local', 'England', 'Essex',                     'essex',                     'ENG', 'E10000012', 15),
  ('ENG_GLOUCESTERSHIRE',    'local', 'England', 'Gloucestershire',           'gloucestershire',           'ENG', 'E10000013', 16),
  ('ENG_GREATER_LONDON',     'local', 'England', 'Greater London',            'greater-london',            'ENG', NULL,        17),
  ('ENG_GREATER_MANCHESTER', 'local', 'England', 'Greater Manchester',        'greater-manchester',        'ENG', NULL,        18),
  ('ENG_HAMPSHIRE',          'local', 'England', 'Hampshire',                 'hampshire',                 'ENG', 'E10000014', 19),
  ('ENG_HEREFORDSHIRE',      'local', 'England', 'Herefordshire',             'herefordshire',             'ENG', NULL,        20),
  ('ENG_HERTFORDSHIRE',      'local', 'England', 'Hertfordshire',             'hertfordshire',             'ENG', 'E10000015', 21),
  ('ENG_ISLE_OF_WIGHT',      'local', 'England', 'Isle of Wight',             'isle-of-wight',             'ENG', NULL,        22),
  ('ENG_ISLES_OF_SCILLY',    'local', 'England', 'Isles of Scilly',           'isles-of-scilly',           'ENG', NULL,        23),
  ('ENG_KENT',               'local', 'England', 'Kent',                      'kent',                      'ENG', 'E10000016', 24),
  ('ENG_LANCASHIRE',         'local', 'England', 'Lancashire',                'lancashire',                'ENG', 'E10000017', 25),
  ('ENG_LEICESTERSHIRE',     'local', 'England', 'Leicestershire',            'leicestershire',            'ENG', 'E10000018', 26),
  ('ENG_LINCOLNSHIRE',       'local', 'England', 'Lincolnshire',              'lincolnshire',              'ENG', 'E10000019', 27),
  ('ENG_MERSEYSIDE',         'local', 'England', 'Merseyside',                'merseyside',                'ENG', NULL,        28),
  ('ENG_NORFOLK',            'local', 'England', 'Norfolk',                   'norfolk',                   'ENG', 'E10000020', 29),
  ('ENG_NORTH_YORKSHIRE',    'local', 'England', 'North Yorkshire',           'north-yorkshire',           'ENG', NULL,        30),
  ('ENG_NORTHAMPTONSHIRE',   'local', 'England', 'Northamptonshire',          'northamptonshire',          'ENG', NULL,        31),
  ('ENG_NORTHUMBERLAND',     'local', 'England', 'Northumberland',            'northumberland',            'ENG', NULL,        32),
  ('ENG_NOTTINGHAMSHIRE',    'local', 'England', 'Nottinghamshire',           'nottinghamshire',           'ENG', 'E10000024', 33),
  ('ENG_OXFORDSHIRE',        'local', 'England', 'Oxfordshire',               'oxfordshire',               'ENG', 'E10000025', 34),
  ('ENG_RUTLAND',            'local', 'England', 'Rutland',                   'rutland',                   'ENG', NULL,        35),
  ('ENG_SHROPSHIRE',         'local', 'England', 'Shropshire',                'shropshire',                'ENG', NULL,        36),
  ('ENG_SOMERSET',           'local', 'England', 'Somerset',                  'somerset',                  'ENG', NULL,        37),
  ('ENG_SOUTH_YORKSHIRE',    'local', 'England', 'South Yorkshire',           'south-yorkshire',           'ENG', NULL,        38),
  ('ENG_STAFFORDSHIRE',      'local', 'England', 'Staffordshire',             'staffordshire',             'ENG', 'E10000028', 39),
  ('ENG_SUFFOLK',            'local', 'England', 'Suffolk',                   'suffolk',                   'ENG', 'E10000029', 40),
  ('ENG_SURREY',             'local', 'England', 'Surrey',                    'surrey',                    'ENG', 'E10000030', 41),
  ('ENG_TYNE_AND_WEAR',      'local', 'England', 'Tyne and Wear',             'tyne-and-wear',             'ENG', NULL,        42),
  ('ENG_WARWICKSHIRE',       'local', 'England', 'Warwickshire',              'warwickshire',              'ENG', 'E10000031', 43),
  ('ENG_WEST_MIDLANDS',      'local', 'England', 'West Midlands',             'west-midlands',             'ENG', NULL,        44),
  ('ENG_WEST_SUSSEX',        'local', 'England', 'West Sussex',               'west-sussex',               'ENG', 'E10000032', 45),
  ('ENG_WEST_YORKSHIRE',     'local', 'England', 'West Yorkshire',            'west-yorkshire',            'ENG', NULL,        46),
  ('ENG_WILTSHIRE',          'local', 'England', 'Wiltshire',                 'wiltshire',                 'ENG', NULL,        47),
  ('ENG_WORCESTERSHIRE',     'local', 'England', 'Worcestershire',            'worcestershire',            'ENG', 'E10000034', 48)
ON CONFLICT (id) DO NOTHING;


-- ──────────────────────────────────────────────────────────
-- Scotland — 32 Council Areas
-- Source: Local Government etc. (Scotland) Act 1994
-- Postcodes.io admin_county = council area name for all
-- Scottish postcodes. Values must match display_name exactly.
-- ONS codes (S12xxxxxx): verify at geoportal.statistics.gov.uk
-- ──────────────────────────────────────────────────────────
INSERT INTO ranking_areas (id, area_type, country, display_name, slug, parent_id, ons_code, sort_order)
VALUES
  ('SCO_ABERDEEN_CITY',         'local', 'Scotland', 'Aberdeen City',          'aberdeen-city',           'SCO', 'S12000033',  1),
  ('SCO_ABERDEENSHIRE',         'local', 'Scotland', 'Aberdeenshire',          'aberdeenshire',           'SCO', 'S12000034',  2),
  ('SCO_ANGUS',                 'local', 'Scotland', 'Angus',                  'angus',                   'SCO', 'S12000041',  3),
  ('SCO_ARGYLL_AND_BUTE',       'local', 'Scotland', 'Argyll and Bute',        'argyll-and-bute',         'SCO', 'S12000035',  4),
  ('SCO_CITY_OF_EDINBURGH',     'local', 'Scotland', 'City of Edinburgh',      'city-of-edinburgh',       'SCO', 'S12000036',  5),
  ('SCO_CLACKMANNANSHIRE',      'local', 'Scotland', 'Clackmannanshire',       'clackmannanshire',        'SCO', 'S12000005',  6),
  ('SCO_DUMFRIES_AND_GALLOWAY', 'local', 'Scotland', 'Dumfries and Galloway',  'dumfries-and-galloway',   'SCO', 'S12000006',  7),
  ('SCO_DUNDEE_CITY',           'local', 'Scotland', 'Dundee City',            'dundee-city',             'SCO', 'S12000042',  8),
  ('SCO_EAST_AYRSHIRE',         'local', 'Scotland', 'East Ayrshire',          'east-ayrshire',           'SCO', 'S12000008',  9),
  ('SCO_EAST_DUNBARTONSHIRE',   'local', 'Scotland', 'East Dunbartonshire',    'east-dunbartonshire',     'SCO', 'S12000045', 10),
  ('SCO_EAST_LOTHIAN',          'local', 'Scotland', 'East Lothian',           'east-lothian',            'SCO', 'S12000010', 11),
  ('SCO_EAST_RENFREWSHIRE',     'local', 'Scotland', 'East Renfrewshire',      'east-renfrewshire',       'SCO', 'S12000011', 12),
  ('SCO_FALKIRK',               'local', 'Scotland', 'Falkirk',                'falkirk',                 'SCO', 'S12000014', 13),
  ('SCO_FIFE',                  'local', 'Scotland', 'Fife',                   'fife',                    'SCO', 'S12000015', 14),
  ('SCO_GLASGOW_CITY',          'local', 'Scotland', 'Glasgow City',           'glasgow-city',            'SCO', 'S12000046', 15),
  ('SCO_HIGHLAND',              'local', 'Scotland', 'Highland',               'highland',                'SCO', 'S12000017', 16),
  ('SCO_INVERCLYDE',            'local', 'Scotland', 'Inverclyde',             'inverclyde',              'SCO', 'S12000018', 17),
  ('SCO_MIDLOTHIAN',            'local', 'Scotland', 'Midlothian',             'midlothian',              'SCO', 'S12000019', 18),
  ('SCO_MORAY',                 'local', 'Scotland', 'Moray',                  'moray',                   'SCO', 'S12000020', 19),
  ('SCO_NA_H_EILEANAN_SIAR',    'local', 'Scotland', 'Na h-Eileanan Siar',     'na-h-eileanan-siar',      'SCO', 'S12000013', 20),
  ('SCO_NORTH_AYRSHIRE',        'local', 'Scotland', 'North Ayrshire',         'north-ayrshire',          'SCO', 'S12000021', 21),
  ('SCO_NORTH_LANARKSHIRE',     'local', 'Scotland', 'North Lanarkshire',      'north-lanarkshire',       'SCO', 'S12000044', 22),
  ('SCO_ORKNEY_ISLANDS',        'local', 'Scotland', 'Orkney Islands',         'orkney-islands',          'SCO', 'S12000023', 23),
  ('SCO_PERTH_AND_KINROSS',     'local', 'Scotland', 'Perth and Kinross',      'perth-and-kinross',       'SCO', 'S12000024', 24),
  ('SCO_RENFREWSHIRE',          'local', 'Scotland', 'Renfrewshire',           'renfrewshire',            'SCO', 'S12000038', 25),
  ('SCO_SCOTTISH_BORDERS',      'local', 'Scotland', 'Scottish Borders',       'scottish-borders',        'SCO', 'S12000026', 26),
  ('SCO_SHETLAND_ISLANDS',      'local', 'Scotland', 'Shetland Islands',       'shetland-islands',        'SCO', 'S12000027', 27),
  ('SCO_SOUTH_AYRSHIRE',        'local', 'Scotland', 'South Ayrshire',         'south-ayrshire',          'SCO', 'S12000028', 28),
  ('SCO_SOUTH_LANARKSHIRE',     'local', 'Scotland', 'South Lanarkshire',      'south-lanarkshire',       'SCO', 'S12000029', 29),
  ('SCO_STIRLING',              'local', 'Scotland', 'Stirling',               'stirling',                'SCO', 'S12000030', 30),
  ('SCO_WEST_DUNBARTONSHIRE',   'local', 'Scotland', 'West Dunbartonshire',    'west-dunbartonshire',     'SCO', 'S12000039', 31),
  ('SCO_WEST_LOTHIAN',          'local', 'Scotland', 'West Lothian',           'west-lothian',            'SCO', 'S12000040', 32)
ON CONFLICT (id) DO NOTHING;


-- ──────────────────────────────────────────────────────────
-- Wales — 22 Principal Areas
-- Source: Local Government (Wales) Act 1994
-- Postcodes.io admin_county = principal area name.
-- display_name uses English-language names as returned by
-- Postcodes.io (e.g. "Isle of Anglesey", not "Ynys Môn").
-- ──────────────────────────────────────────────────────────
INSERT INTO ranking_areas (id, area_type, country, display_name, slug, parent_id, ons_code, sort_order)
VALUES
  ('WLS_BLAENAU_GWENT',     'local', 'Wales', 'Blaenau Gwent',     'blaenau-gwent',       'WLS', 'W06000019',  1),
  ('WLS_BRIDGEND',          'local', 'Wales', 'Bridgend',          'bridgend',            'WLS', 'W06000013',  2),
  ('WLS_CAERPHILLY',        'local', 'Wales', 'Caerphilly',        'caerphilly',          'WLS', 'W06000018',  3),
  ('WLS_CARDIFF',           'local', 'Wales', 'Cardiff',           'cardiff',             'WLS', 'W06000015',  4),
  ('WLS_CARMARTHENSHIRE',   'local', 'Wales', 'Carmarthenshire',   'carmarthenshire',     'WLS', 'W06000010',  5),
  ('WLS_CEREDIGION',        'local', 'Wales', 'Ceredigion',        'ceredigion',          'WLS', 'W06000008',  6),
  ('WLS_CONWY',             'local', 'Wales', 'Conwy',             'conwy',               'WLS', 'W06000003',  7),
  ('WLS_DENBIGHSHIRE',      'local', 'Wales', 'Denbighshire',      'denbighshire',        'WLS', 'W06000004',  8),
  ('WLS_FLINTSHIRE',        'local', 'Wales', 'Flintshire',        'flintshire',          'WLS', 'W06000005',  9),
  ('WLS_GWYNEDD',           'local', 'Wales', 'Gwynedd',           'gwynedd',             'WLS', 'W06000002', 10),
  ('WLS_ISLE_OF_ANGLESEY',  'local', 'Wales', 'Isle of Anglesey',  'isle-of-anglesey',    'WLS', 'W06000001', 11),
  ('WLS_MERTHYR_TYDFIL',    'local', 'Wales', 'Merthyr Tydfil',    'merthyr-tydfil',      'WLS', 'W06000024', 12),
  ('WLS_MONMOUTHSHIRE',     'local', 'Wales', 'Monmouthshire',     'monmouthshire',       'WLS', 'W06000021', 13),
  ('WLS_NEATH_PORT_TALBOT', 'local', 'Wales', 'Neath Port Talbot', 'neath-port-talbot',   'WLS', 'W06000012', 14),
  ('WLS_NEWPORT',           'local', 'Wales', 'Newport',           'newport',             'WLS', 'W06000022', 15),
  ('WLS_PEMBROKESHIRE',     'local', 'Wales', 'Pembrokeshire',     'pembrokeshire',       'WLS', 'W06000009', 16),
  ('WLS_POWYS',             'local', 'Wales', 'Powys',             'powys',               'WLS', 'W06000023', 17),
  ('WLS_RHONDDA_CYNON_TAF', 'local', 'Wales', 'Rhondda Cynon Taf', 'rhondda-cynon-taf',   'WLS', 'W06000016', 18),
  ('WLS_SWANSEA',           'local', 'Wales', 'Swansea',           'swansea',             'WLS', 'W06000011', 19),
  ('WLS_TORFAEN',           'local', 'Wales', 'Torfaen',           'torfaen',             'WLS', 'W06000020', 20),
  ('WLS_VALE_OF_GLAMORGAN', 'local', 'Wales', 'Vale of Glamorgan', 'vale-of-glamorgan',   'WLS', 'W06000014', 21),
  ('WLS_WREXHAM',           'local', 'Wales', 'Wrexham',           'wrexham',             'WLS', 'W06000006', 22)
ON CONFLICT (id) DO NOTHING;


-- ──────────────────────────────────────────────────────────
-- Northern Ireland — 11 Districts
-- Source: Local Government Act (NI) 2014, effective 2015
-- Postcodes.io returns admin_district = district name;
-- admin_county = NULL for all NI postcodes.
-- Resolution is via cc_lad_to_county crosswalk (file 03).
-- ──────────────────────────────────────────────────────────
INSERT INTO ranking_areas (id, area_type, country, display_name, slug, parent_id, ons_code, sort_order)
VALUES
  ('NIR_ANTRIM_AND_NEWTOWNABBEY',     'local', 'Northern Ireland', 'Antrim and Newtownabbey',               'antrim-and-newtownabbey',            'NIR', 'N09000001',  1),
  ('NIR_ARDS_AND_NORTH_DOWN',         'local', 'Northern Ireland', 'Ards and North Down',                   'ards-and-north-down',                'NIR', 'N09000011',  2),
  ('NIR_ARMAGH_BANBRIDGE_CRAIGAVON',  'local', 'Northern Ireland', 'Armagh City, Banbridge and Craigavon',  'armagh-city-banbridge-and-craigavon', 'NIR', 'N09000002',  3),
  ('NIR_BELFAST',                     'local', 'Northern Ireland', 'Belfast',                               'belfast',                            'NIR', 'N09000003',  4),
  ('NIR_CAUSEWAY_COAST_AND_GLENS',    'local', 'Northern Ireland', 'Causeway Coast and Glens',              'causeway-coast-and-glens',           'NIR', 'N09000004',  5),
  ('NIR_DERRY_AND_STRABANE',          'local', 'Northern Ireland', 'Derry City and Strabane',               'derry-city-and-strabane',            'NIR', 'N09000005',  6),
  ('NIR_FERMANAGH_AND_OMAGH',         'local', 'Northern Ireland', 'Fermanagh and Omagh',                   'fermanagh-and-omagh',                'NIR', 'N09000006',  7),
  ('NIR_LISBURN_AND_CASTLEREAGH',     'local', 'Northern Ireland', 'Lisburn and Castlereagh',               'lisburn-and-castlereagh',            'NIR', 'N09000007',  8),
  ('NIR_MID_AND_EAST_ANTRIM',         'local', 'Northern Ireland', 'Mid and East Antrim',                   'mid-and-east-antrim',                'NIR', 'N09000008',  9),
  ('NIR_MID_ULSTER',                  'local', 'Northern Ireland', 'Mid Ulster',                            'mid-ulster',                         'NIR', 'N09000009', 10),
  ('NIR_NEWRY_MOURNE_AND_DOWN',       'local', 'Northern Ireland', 'Newry, Mourne and Down',                'newry-mourne-and-down',               'NIR', 'N09000010', 11)
ON CONFLICT (id) DO NOTHING;
