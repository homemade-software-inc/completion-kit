models = [
  { provider: "openai", model_id: "gpt-5.4-mini", display_name: "GPT-5.4 Mini", status: "active", supports_generation: true, supports_judging: true, probed_at: Time.current, discovered_at: Time.current },
  { provider: "openai", model_id: "gpt-4.1-mini", display_name: "GPT-4.1 Mini", status: "active", supports_generation: true, supports_judging: true, probed_at: Time.current, discovered_at: Time.current },
  { provider: "openai", model_id: "gpt-4o-mini", display_name: "GPT-4o Mini", status: "active", supports_generation: true, supports_judging: true, probed_at: Time.current, discovered_at: Time.current },
  { provider: "anthropic", model_id: "claude-sonnet-4-6", display_name: "Claude Sonnet 4.6", status: "active", supports_generation: true, supports_judging: true, probed_at: Time.current, discovered_at: Time.current },
  { provider: "anthropic", model_id: "claude-haiku-4-5", display_name: "Claude Haiku 4.5", status: "active", supports_generation: true, supports_judging: true, probed_at: Time.current, discovered_at: Time.current }
]

models.each do |attrs|
  CompletionKit::Model.find_or_create_by!(provider: attrs[:provider], model_id: attrs[:model_id]) do |m|
    m.assign_attributes(attrs)
  end
end

accuracy = CompletionKit::Metric.find_or_create_by!(name: "Accuracy") do |m|
  m.instruction = "Does the listing description accurately reflect the property details provided? It must not invent features, amenities, or characteristics that are not in the input."
  m.rubric_bands = [
    { "stars" => 5, "description" => "Every claim in the listing is verifiable from the input. No invented features. No exaggerated sizes or distances. All key property details are represented." },
    { "stars" => 4, "description" => "One minor embellishment or slight exaggeration (e.g. 'moments from the beach' when input says 200m). All major details are accurate." },
    { "stars" => 3, "description" => "Mostly accurate but includes one invented detail (e.g. mentions a garden that isn't in the input) or misrepresents a key fact like bedroom count or land size." },
    { "stars" => 2, "description" => "Multiple fabricated details or significant misrepresentations. A buyer reading this would form a materially incorrect impression of the property." },
    { "stars" => 1, "description" => "The listing bears little resemblance to the actual property. Major features are invented, key details are wrong, or the property type itself is mischaracterised." }
  ]
end

persuasiveness = CompletionKit::Metric.find_or_create_by!(name: "Persuasiveness") do |m|
  m.instruction = "Would this listing make a potential buyer want to inspect the property? Does it paint a compelling picture of the lifestyle and appeal?"
  m.rubric_bands = [
    { "stars" => 5, "description" => "Immediately compelling. Creates a vivid sense of the lifestyle. Key features are positioned as benefits, not just specs. You want to see the property after reading this." },
    { "stars" => 4, "description" => "Engaging and well-structured. Most features connect to lifestyle benefits. Creates interest but doesn't quite make you reach for the phone." },
    { "stars" => 3, "description" => "Reads more like a feature list than a story. Covers the basics but doesn't differentiate the property or create emotional appeal." },
    { "stars" => 2, "description" => "Flat and forgettable. Could describe almost any property in the area. No sense of what makes this one special." },
    { "stars" => 1, "description" => "Actively off-putting. Dry specification dump, or so generic it suggests the writer didn't read the brief. Zero desire to inspect." }
  ]
end

tone = CompletionKit::Metric.find_or_create_by!(name: "Tone") do |m|
  m.instruction = "Is the tone professional and appropriate for a real estate listing? It should be confident and appealing without being pushy, exaggerated, or sounding like a used car ad."
  m.rubric_bands = [
    { "stars" => 5, "description" => "Reads like it was written by a top-tier agency. Confident, measured, specific. Lets the property speak for itself. Zero pressure language or empty superlatives." },
    { "stars" => 4, "description" => "Professional and appropriate. One or two slightly enthusiastic phrases but nothing that undermines credibility." },
    { "stars" => 3, "description" => "Serviceable but generic. Some stock phrases ('ideal for families', 'great investment') that add nothing. Not embarrassing but not polished." },
    { "stars" => 2, "description" => "Veers into salesy territory. Multiple exclamation marks, pressure tactics, or breathless superlatives that erode trust." },
    { "stars" => 1, "description" => "Used-car-ad energy. 'DON'T MISS THIS INCREDIBLE OPPORTUNITY!!!' territory. Would make a serious buyer scroll past." }
  ]
end

criteria = CompletionKit::Criteria.find_or_create_by!(name: "Listing Quality") do |c|
  c.description = "Full quality assessment for property listing descriptions"
end
[accuracy, persuasiveness, tone].each_with_index do |metric, i|
  CompletionKit::CriteriaMembership.find_or_create_by!(criteria: criteria, metric: metric) do |cm|
    cm.position = i + 1
  end
end

csv_data = <<~CSV
property_details
"3 bedroom weatherboard house in Brunswick, Melbourne. 620sqm block. Renovated kitchen with stone benchtops and Smeg appliances. Original hardwood floors throughout. North-facing backyard with established lemon tree and veggie patch. Single carport. Walking distance to Sydney Road trams and cafes. Zoned for Brunswick Secondary College."
"2 bedroom apartment on level 12 in Surfers Paradise, Gold Coast. Ocean views from living room and main bedroom. 87sqm internal plus 15sqm balcony. Resort-style pool, gym, and sauna in building. Secure parking for one car. 200m walk to the beach. Currently tenanted at $650/week."
"5 bedroom colonial homestead on 42 acres in Daylesford, Victoria. Built 1890, fully restored. 4 bathrooms, formal dining, library, and wrap-around verandah. Spring-fed dam, established gardens with heritage roses. Separate 2-bedroom guest cottage. 90 minutes from Melbourne CBD."
"1 bedroom studio in Potts Point, Sydney. 38sqm. Art deco building with original features. Built-in wardrobe, updated bathroom. Shared rooftop terrace with harbour glimpses. No parking. Strata $900/quarter. Walk to Kings Cross station and Woolloomooloo wharf."
"4 bedroom brick home in Paddington, Brisbane. 450sqm block. Queenslander style with wide front verandah. Open plan living flowing to deck overlooking the city skyline. Two bathrooms, powder room. Lock-up garage for two cars. Quiet street, 3km to CBD. Near Suncorp Stadium and Caxton Street."
CSV

dataset = CompletionKit::Dataset.find_or_create_by!(name: "Property Listings — AU") do |d|
  d.csv_data = csv_data
end

prompt = CompletionKit::Prompt.find_or_create_by!(name: "Property Listing Generator") do |p|
  p.description = "Generates real estate listing descriptions from structured property details"
  p.template = "Write a compelling property listing description for this property. Highlight key features, neighbourhood appeal, and lifestyle. Be professional but engaging. Under 200 words.\n\n{{property_details}}"
  p.llm_model = "gpt-4.1-mini"
end

run = CompletionKit::Run.find_or_create_by!(name: "Property Listing Generator — v1 #1") do |r|
  r.prompt = prompt
  r.dataset = dataset
  r.judge_model = "gpt-4.1-mini"
  r.status = "completed"
  r.progress_current = 15
  r.progress_total = 15
end

[accuracy, persuasiveness, tone].each_with_index do |metric, i|
  CompletionKit::RunMetric.find_or_create_by!(run: run, metric: metric) do |rm|
    rm.position = i + 1
  end
end

responses_data = [
  {
    input: csv_data.lines[1].strip.tr('"', ''),
    text: "Welcome to this beautifully renovated 3-bedroom weatherboard home in the heart of Brunswick. Original hardwood floors flow through light-filled living spaces, while the modern kitchen — complete with stone benchtops and Smeg appliances — is ready for serious home cooks. Step outside to a generous north-facing backyard where an established lemon tree and thriving veggie patch set the scene for weekend mornings with coffee in hand. A single carport keeps things practical, and the location is hard to beat: Sydney Road trams, cafes, and local shops are all within walking distance. Zoned for Brunswick Secondary College, this is a home that balances character and convenience in one of Melbourne's most sought-after inner-north pockets.",
    scores: { "Accuracy" => [5, "Every detail matches the input — no fabrications. Kitchen specs, backyard features, zoning, and location are all accurately represented."],
              "Persuasiveness" => [4, "Paints a nice lifestyle picture with the weekend coffee scene. Could push harder on the neighbourhood appeal."],
              "Tone" => [5, "Professional, warm, reads like a quality agent listing. No hyperbole."] }
  },
  {
    input: csv_data.lines[2].strip.tr('"', ''),
    text: "Perched on level 12 with sweeping ocean views, this stunning 2-bedroom apartment is your gateway to the ultimate Gold Coast lifestyle! Wake up to the sound of waves and step onto your private 15sqm balcony for morning coffee with a view that will take your breath away. The resort-style facilities — pool, gym, and sauna — mean every day feels like a holiday. Just 200 metres to the beach and currently returning $650/week, this is an incredible opportunity for investors and lifestyle buyers alike. Don't miss out on this absolute gem — properties like this don't last long!",
    scores: { "Accuracy" => [4, "Details are mostly accurate but 'sound of waves from level 12' is a stretch. Investment return mentioned correctly."],
              "Persuasiveness" => [4, "Strong lifestyle appeal and investment angle. The urgency at the end is effective if a bit much."],
              "Tone" => [2, "Too many exclamation marks. 'Don't miss out' and 'absolute gem' push into used-car-ad territory. Needs more restraint."] }
  },
  {
    input: csv_data.lines[3].strip.tr('"', ''),
    text: "A rare offering in the Daylesford hinterland — this meticulously restored 1890s colonial homestead sits on 42 acres of rolling countryside. Five bedrooms, four bathrooms, a formal dining room, and a library provide generous proportions for family life and entertaining. The wrap-around verandah frames views across established gardens where heritage roses bloom beside a spring-fed dam. A separate 2-bedroom guest cottage offers flexibility for extended family or income. Just 90 minutes from Melbourne, this is a property that rewards the drive with a pace of life that simply can't be found in the city.",
    scores: { "Accuracy" => [5, "Faithfully represents every detail from the input. No invented features. Heritage character captured well."],
              "Persuasiveness" => [5, "The closing line about 'rewarding the drive' is excellent. Creates genuine desire to visit."],
              "Tone" => [5, "Measured, elegant, exactly right for a prestige country property. Reads like a premium agency listing."] }
  },
  {
    input: csv_data.lines[4].strip.tr('"', ''),
    text: "This character-filled 1-bedroom studio in a heritage art deco building offers a foothold in one of Sydney's most vibrant neighbourhoods. At 38sqm it's compact but cleverly laid out with a built-in wardrobe and updated bathroom. The shared rooftop terrace delivers harbour glimpses — your evening drink spot sorted. No car needed here: Kings Cross station is a short walk, and Woolloomooloo wharf, the Botanic Gardens, and the city are all on your doorstep. Strata of $900 per quarter keeps costs manageable. For first-home buyers or investors wanting a blue-chip inner-city address, this is worth a serious look.",
    scores: { "Accuracy" => [5, "All details match. Correctly notes no parking, strata costs, and shared rooftop. No fabrications."],
              "Persuasiveness" => [4, "Good positioning for the target buyer. The rooftop terrace angle is smart. Could do more with the neighbourhood lifestyle."],
              "Tone" => [4, "Professional and honest about the size. 'Evening drink spot sorted' is slightly casual but works for the market."] }
  },
  {
    input: csv_data.lines[5].strip.tr('"', ''),
    text: "Situated in a quiet Paddington street just 3km from the Brisbane CBD, this classic Queenslander has been thoughtfully updated for modern family living. Four bedrooms, two bathrooms, and a powder room provide space for a growing household, while the wide front verandah is quintessential Brisbane. The open-plan living area flows seamlessly to a rear deck where city skyline views make entertaining effortless. A lock-up double garage rounds out the practical side, and the location near Suncorp Stadium and Caxton Street means weekend plans are always walking distance away.",
    scores: { "Accuracy" => [5, "Every detail accurately represented. Block size, rooms, garage, location — all match the input."],
              "Persuasiveness" => [4, "Solid lifestyle appeal with the entertaining deck and weekend walkability. The skyline views could be played up more."],
              "Tone" => [5, "Clean, professional, confident. Exactly the right register for a family Queenslander listing."] }
  }
]

responses_data.each do |rd|
  response = run.responses.find_or_create_by!(input_data: rd[:input]) do |r|
    r.response_text = rd[:text]
  end

  rd[:scores].each do |metric_name, (score, feedback)|
    metric = CompletionKit::Metric.find_by!(name: metric_name)
    response.reviews.find_or_create_by!(metric: metric) do |review|
      review.metric_name = metric_name
      review.instruction = metric.instruction
      review.status = "evaluated"
      review.ai_score = score
      review.ai_feedback = feedback
    end
  end
end

conciseness = CompletionKit::Metric.find_or_create_by!(name: "Conciseness") do |m|
  m.instruction = "Is the summary the right length? It should be exactly 2 sentences and convey the essential property information without filler."
  m.rubric_bands = [
    { "stars" => 5, "description" => "Exactly 2 sentences. Every word earns its place. Works perfectly as a search snippet." },
    { "stars" => 3, "description" => "Close to 2 sentences but slightly too long or includes filler words that add nothing." },
    { "stars" => 1, "description" => "Way too long, way too short, or reads like a full listing crammed into two lines." }
  ]
end

completeness = CompletionKit::Metric.find_or_create_by!(name: "Completeness") do |m|
  m.instruction = "Does the summary capture what a buyer scanning search results would most want to know? Key selling point, location, and property type at minimum."
  m.rubric_bands = [
    { "stars" => 5, "description" => "Covers property type, location, and the standout feature. A buyer knows immediately whether to click through." },
    { "stars" => 3, "description" => "Covers basics but misses the hook. You know what it is but not why you'd care." },
    { "stars" => 1, "description" => "Missing critical information. You can't tell what kind of property it is or where." }
  ]
end

local_relevance = CompletionKit::Metric.find_or_create_by!(name: "Local Relevance") do |m|
  m.instruction = "Does the neighbourhood description reflect the specific character of this area? It should feel like the writer has actually been there, not like a generic suburb template."
  m.rubric_bands = [
    { "stars" => 5, "description" => "Clearly about this specific neighbourhood. Names local landmarks or captures the area's known character accurately." },
    { "stars" => 3, "description" => "Broadly correct but could describe several similar suburbs. Generic 'great cafes and parks' territory." },
    { "stars" => 1, "description" => "Wrong vibe entirely, or so generic it adds nothing. Could be any suburb in Australia." }
  ]
end

engagement = CompletionKit::Metric.find_or_create_by!(name: "Engagement") do |m|
  m.instruction = "Does the neighbourhood guide make you want to live there? It should paint a picture of the lifestyle, not just list amenities."
  m.rubric_bands = [
    { "stars" => 5, "description" => "You can picture yourself there. The writing connects place to lifestyle. Creates genuine pull." },
    { "stars" => 3, "description" => "Pleasant but forgettable. Lists amenities without connecting them to how life actually feels there." },
    { "stars" => 1, "description" => "Dry, clinical, or completely fails to convey any sense of place. Reads like a council report." }
  ]
end

summary_criteria = CompletionKit::Criteria.find_or_create_by!(name: "Search Snippet Quality") do |c|
  c.description = "Assessment criteria for property search-result summaries"
end
[accuracy, conciseness, completeness].each_with_index do |metric, i|
  CompletionKit::CriteriaMembership.find_or_create_by!(criteria: summary_criteria, metric: metric) do |cm|
    cm.position = i + 1
  end
end

neighbourhood_criteria = CompletionKit::Criteria.find_or_create_by!(name: "Neighbourhood Guide Quality") do |c|
  c.description = "Assessment criteria for neighbourhood lifestyle descriptions"
end
[accuracy, local_relevance, engagement].each_with_index do |metric, i|
  CompletionKit::CriteriaMembership.find_or_create_by!(criteria: neighbourhood_criteria, metric: metric) do |cm|
    cm.position = i + 1
  end
end

summary_prompt = CompletionKit::Prompt.find_or_create_by!(name: "Property Summary") do |p|
  p.description = "Generates a 2-sentence search-result snippet from property details"
  p.template = "Write a 2-sentence property summary for use in search results. Include the key selling point and the property type. Be factual and concise.\n\n{{property_details}}"
  p.llm_model = "gpt-4.1-mini"
end

summary_run = CompletionKit::Run.find_or_create_by!(name: "Property Summary — v1 #1") do |r|
  r.prompt = summary_prompt
  r.dataset = dataset
  r.judge_model = "gpt-4.1-mini"
  r.status = "completed"
  r.progress_current = 15
  r.progress_total = 15
end

[accuracy, conciseness, completeness].each_with_index do |metric, i|
  CompletionKit::RunMetric.find_or_create_by!(run: summary_run, metric: metric) do |rm|
    rm.position = i + 1
  end
end

summary_responses = [
  { input: csv_data.lines[1].strip.tr('"', ''),
    text: "Renovated 3-bedroom weatherboard in Brunswick with original hardwood floors and a north-facing backyard. Walking distance to Sydney Road trams and zoned for Brunswick Secondary College.",
    scores: { "Accuracy" => [5, "All details verifiable from the input."], "Conciseness" => [5, "Exactly 2 sentences, no filler."], "Completeness" => [5, "Property type, location, key features, and school zone covered."] } },
  { input: csv_data.lines[2].strip.tr('"', ''),
    text: "Level 12 ocean-view apartment in Surfers Paradise with resort-style facilities and secure parking. Currently tenanted at $650/week, 200m from the beach.",
    scores: { "Accuracy" => [5, "All claims match the input."], "Conciseness" => [5, "Two tight sentences."], "Completeness" => [4, "Covers the essentials but doesn't mention the 87sqm size which buyers would want."] } },
  { input: csv_data.lines[3].strip.tr('"', ''),
    text: "Fully restored 1890s colonial homestead on 42 acres in Daylesford with five bedrooms, a guest cottage, and heritage gardens. Ninety minutes from Melbourne.",
    scores: { "Accuracy" => [5, "Faithful to the input."], "Conciseness" => [5, "Two sentences, well-packed."], "Completeness" => [5, "Property type, era, land size, key features, and distance to Melbourne all present."] } },
  { input: csv_data.lines[4].strip.tr('"', ''),
    text: "Compact 1-bedroom art deco studio in Potts Point with harbour glimpses from the shared rooftop terrace. Walk to Kings Cross station, strata $900/quarter.",
    scores: { "Accuracy" => [5, "All details match."], "Conciseness" => [5, "Two sentences."], "Completeness" => [4, "Good but 'compact' understates 38sqm. Size might be worth mentioning explicitly."] } },
  { input: csv_data.lines[5].strip.tr('"', ''),
    text: "Classic 4-bedroom Queenslander in Paddington with city skyline views from the rear deck. Quiet street, 3km to Brisbane CBD, near Suncorp Stadium.",
    scores: { "Accuracy" => [5, "Matches the input."], "Conciseness" => [5, "Two sentences."], "Completeness" => [5, "Property type, style, key feature, and location context all covered."] } }
]

summary_responses.each do |rd|
  response = summary_run.responses.find_or_create_by!(input_data: rd[:input]) do |r|
    r.response_text = rd[:text]
  end
  rd[:scores].each do |metric_name, (score, feedback)|
    metric = CompletionKit::Metric.find_by!(name: metric_name)
    response.reviews.find_or_create_by!(metric: metric) do |review|
      review.metric_name = metric_name
      review.instruction = metric.instruction
      review.status = "evaluated"
      review.ai_score = score
      review.ai_feedback = feedback
    end
  end
end

neighbourhood_prompt = CompletionKit::Prompt.find_or_create_by!(name: "Neighbourhood Guide") do |p|
  p.description = "Generates a lifestyle paragraph about the area surrounding a property"
  p.template = "Write a short paragraph about the neighbourhood and lifestyle around this property. Focus on what it's like to live there, not the property itself. Under 100 words.\n\n{{property_details}}"
  p.llm_model = "claude-sonnet-4-6"
end

neighbourhood_run = CompletionKit::Run.find_or_create_by!(name: "Neighbourhood Guide — v1 #1") do |r|
  r.prompt = neighbourhood_prompt
  r.dataset = dataset
  r.judge_model = "gpt-4.1-mini"
  r.status = "completed"
  r.progress_current = 15
  r.progress_total = 15
end

[accuracy, local_relevance, engagement].each_with_index do |metric, i|
  CompletionKit::RunMetric.find_or_create_by!(run: neighbourhood_run, metric: metric) do |rm|
    rm.position = i + 1
  end
end

neighbourhood_responses = [
  { input: csv_data.lines[1].strip.tr('"', ''),
    text: "Brunswick is Melbourne's inner north at its most liveable. Sydney Road is the spine of the neighbourhood: trams, Lebanese bakeries, vintage shops, and cheap pho all within a few blocks. Weekend mornings mean coffee at one of a dozen roasters, a lap of the Merri Creek trail, and groceries from the organic co-op. It's the kind of suburb where your neighbours know your dog's name and the local pub has live music on Thursdays.",
    scores: { "Accuracy" => [5, "Sydney Road, trams, Merri Creek, inner north positioning all accurate."], "Local Relevance" => [5, "Names specific landmarks and captures Brunswick's character precisely."], "Engagement" => [5, "The dog's name detail and Thursday pub music paint a vivid, specific picture of the lifestyle."] } },
  { input: csv_data.lines[2].strip.tr('"', ''),
    text: "Surfers Paradise lives up to the name if you like your mornings with salt air and your evenings with options. The beach is the obvious draw, but the light-rail connects you to Broadbeach dining and Pacific Fair shopping without touching a car. The foreshore parklands are the local living room: runners, families, and tourists sharing the same stretch of green between the high-rises and the sand.",
    scores: { "Accuracy" => [4, "Light rail and Broadbeach connection accurate. Pacific Fair is technically in Broadbeach, not Surfers, but accessible."], "Local Relevance" => [4, "Captures the Surfers vibe well but could distinguish it more from the broader Gold Coast."], "Engagement" => [4, "Good sensory detail with the salt air opener. The 'local living room' metaphor works."] } },
  { input: csv_data.lines[3].strip.tr('"', ''),
    text: "Daylesford is the spa country town that Melbourne escapes to. Mineral springs, galleries, and restaurants that punch well above their weight for a town of 3,000. The Saturday market at the old railway station is the social hub. Hepburn Springs is a five-minute drive. The pace is deliberately slow and the community is tight: you'll see the same faces at the general store and the bookshop.",
    scores: { "Accuracy" => [5, "Mineral springs, market, Hepburn Springs proximity all accurate. Town character well captured."], "Local Relevance" => [5, "Deeply specific to Daylesford. The market, general store, and bookshop details could only be this town."], "Engagement" => [5, "Makes you want to move there. The 'deliberately slow' framing is perfect for the audience."] } },
  { input: csv_data.lines[4].strip.tr('"', ''),
    text: "Potts Point is Sydney's most walkable neighbourhood. The strip of cafes and restaurants along Macleay Street has enough range to eat somewhere different every night for a month. The Botanic Gardens and the harbour foreshore are a ten-minute walk. Kings Cross station puts the CBD five minutes away. It's dense and urban but with enough old fig trees and art deco architecture to feel like a village inside the city.",
    scores: { "Accuracy" => [5, "Macleay Street, Kings Cross station, Botanic Gardens proximity all correct."], "Local Relevance" => [5, "Captures Potts Point specifically, not just generic Sydney. The Macleay Street and fig trees details are spot on."], "Engagement" => [4, "Solid sense of place. The 'village inside the city' line lands well but could push the lifestyle picture harder."] } },
  { input: csv_data.lines[5].strip.tr('"', ''),
    text: "Paddington is where Brisbane's Queenslander charm meets inner-city convenience. Given Road and Latrobe Terrace have the cafes and weekend brunch crowds, while Suncorp Stadium brings the energy on game nights. Caxton Street is the pub precinct, but the quieter residential streets behind it are the real appeal: wide verandahs, mango trees, and a pace that feels a decade behind the CBD three kilometres away.",
    scores: { "Accuracy" => [5, "Given Road, Latrobe Terrace, Suncorp, Caxton Street all correctly placed. CBD distance matches."], "Local Relevance" => [5, "Deeply specific to Paddington, Brisbane. The mango trees and wide verandahs are quintessential details."], "Engagement" => [5, "The contrast between game-night energy and quiet residential streets is exactly how locals describe Paddington."] } }
]

neighbourhood_responses.each do |rd|
  response = neighbourhood_run.responses.find_or_create_by!(input_data: rd[:input]) do |r|
    r.response_text = rd[:text]
  end
  rd[:scores].each do |metric_name, (score, feedback)|
    metric = CompletionKit::Metric.find_by!(name: metric_name)
    response.reviews.find_or_create_by!(metric: metric) do |review|
      review.metric_name = metric_name
      review.instruction = metric.instruction
      review.status = "evaluated"
      review.ai_score = score
      review.ai_feedback = feedback
    end
  end
end

puts "Seeded: #{CompletionKit::Model.count} models, #{CompletionKit::Prompt.count} prompts, #{CompletionKit::Dataset.count} datasets, #{CompletionKit::Metric.count} metrics, #{CompletionKit::Run.count} runs, #{CompletionKit::Response.count} responses, #{CompletionKit::Review.count} reviews"
