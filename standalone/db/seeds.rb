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
  m.evaluation_steps = [
    "Read the property details input carefully",
    "Check every claim in the listing against the input",
    "Flag any invented or fabricated details",
    "Score based on how faithfully the listing represents the actual property"
  ]
end

persuasiveness = CompletionKit::Metric.find_or_create_by!(name: "Persuasiveness") do |m|
  m.instruction = "Would this listing make a potential buyer want to inspect the property? Does it paint a compelling picture of the lifestyle and appeal?"
  m.evaluation_steps = [
    "Read the listing as if you were a buyer searching for this type of property",
    "Does it highlight the most appealing features?",
    "Does it create a sense of place and lifestyle?",
    "Would you want to book an inspection after reading this?"
  ]
end

tone = CompletionKit::Metric.find_or_create_by!(name: "Tone") do |m|
  m.instruction = "Is the tone professional and appropriate for a real estate listing? It should be confident and appealing without being pushy, exaggerated, or sounding like a used car ad."
  m.evaluation_steps = [
    "Check for hyperbolic language or excessive exclamation marks",
    "Look for pressure tactics or urgency that feels forced",
    "Assess whether it reads like a professional agent wrote it",
    "Verify it strikes the right balance between informative and engaging"
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

puts "Seeded: #{CompletionKit::Model.count} models, #{CompletionKit::Prompt.count} prompts, #{CompletionKit::Dataset.count} datasets, #{CompletionKit::Metric.count} metrics, #{CompletionKit::Run.count} runs, #{CompletionKit::Response.count} responses, #{CompletionKit::Review.count} reviews"
