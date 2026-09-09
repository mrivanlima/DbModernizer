const pptxgen = require("pptxgenjs");

const NAVY = "0F2540";
const TEAL = "8FD3C7";
const ICE = "C9D9E3";
const WHITE = "FFFFFF";
const SLATE = "3A4A5A";

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.3 x 7.5

// ---------- Slide 1: Title ----------
{
  const slide = pres.addSlide();
  slide.background = { color: NAVY };
  slide.addShape(pres.ShapeType.ellipse, {
    x: 10.3, y: -1.5, w: 4.5, h: 4.5, fill: { color: TEAL, transparency: 88 }, line: { type: "none" }
  });
  slide.addShape(pres.ShapeType.ellipse, {
    x: -1.8, y: 5.2, w: 3.6, h: 3.6, fill: { color: TEAL, transparency: 90 }, line: { type: "none" }
  });
  slide.addText("Agentic AI Data Migration", {
    x: 0.8, y: 2.5, w: 11.7, h: 1.2, fontFace: "Cambria", fontSize: 40, bold: true, color: WHITE, isTextBox: true, margin: 0
  });
  slide.addText('What "AI Doing the Migration" Actually Means Now', {
    x: 0.8, y: 3.6, w: 11.7, h: 0.7, fontFace: "Calibri", fontSize: 20, color: TEAL, isTextBox: true, margin: 0
  });
  slide.addText("Ivan Lima  ·  Data Platform Advisory", {
    x: 0.8, y: 6.5, w: 8, h: 0.5, fontFace: "Calibri", fontSize: 14, color: ICE, isTextBox: true, margin: 0
  });
  slide.addNotes("Hey, I'm Ivan Lima with Data Platform Advisory. Today we're talking about agentic AI and data migration, and specifically, what it actually means when someone tells you 'AI is doing the migration.' Because in 2026, that phrase gets thrown around a lot, and it usually means something very different from what people picture.");
}

// ---------- Slide 2: Hook / problem ----------
{
  const slide = pres.addSlide();
  slide.background = { color: WHITE };
  slide.addText("The phrase everyone's using", {
    x: 0.6, y: 0.5, w: 12, h: 0.8, fontFace: "Cambria", fontSize: 30, bold: true, color: NAVY, isTextBox: true, margin: 0
  });
  slide.addShape(pres.ShapeType.roundRect, {
    x: 0.8, y: 1.8, w: 11.6, h: 2.0, rectRadius: 0.12,
    fill: { color: NAVY }, line: { type: "none" },
    shadow: { type: "outer", color: "000000", opacity: 0.25, blur: 8, offset: 3, angle: 90 }
  });
  slide.addText('"AI is doing the migration"', {
    x: 1.2, y: 2.15, w: 10.8, h: 1.3, fontFace: "Cambria", fontSize: 30, italic: true, bold: true, color: TEAL,
    align: "center", isTextBox: true, margin: 0
  });
  slide.addText("Two very different things could be meant by this sentence — and in 2026, the wrong assumption has already cost companies their production databases.", {
    x: 0.8, y: 4.3, w: 11.6, h: 1.4, fontFace: "Calibri", fontSize: 18, color: SLATE, isTextBox: true, margin: 0
  });
  slide.addNotes("Here's the phrase: 'AI is doing the migration.' Sounds simple, right? But that sentence can mean two very different things. It can mean an agent is helping with discovery and translation while a human still approves the risky steps. Or it can mean an agent has full, unsupervised access to your production database. Mixing those two up isn't a technicality — it's already caused real, documented incidents this year.");
}

// ---------- Slide 3: What it actually means (two column) ----------
{
  const slide = pres.addSlide();
  slide.background = { color: NAVY };
  slide.addText("What it means vs. what it should mean", {
    x: 0.6, y: 0.45, w: 12, h: 0.8, fontFace: "Cambria", fontSize: 28, bold: true, color: WHITE, isTextBox: true, margin: 0
  });

  // Left card - marketing claim
  slide.addShape(pres.ShapeType.roundRect, {
    x: 0.7, y: 1.6, w: 5.7, h: 5.2, rectRadius: 0.12, fill: { color: "16324f" }, line: { color: "3A4A5A", width: 1 }
  });
  slide.addText("The pitch", { x: 1.0, y: 1.85, w: 5.1, h: 0.5, fontFace: "Cambria", fontSize: 18, bold: true, color: TEAL, isTextBox: true, margin: 0 });
  slide.addText(
    [
      { text: "Agent connects to production", options: { bullet: true, breakLine: true } },
      { text: "Runs the whole migration end to end", options: { bullet: true, breakLine: true } },
      { text: "No human in the loop needed", options: { bullet: true, breakLine: true } },
      { text: "\"Fire and forget\"", options: { bullet: true, breakLine: false } },
    ],
    { x: 1.0, y: 2.5, w: 5.1, h: 3.8, fontFace: "Calibri", fontSize: 16, color: ICE, isTextBox: true, margin: 0, paraSpaceAfter: 14 }
  );

  // Right card - reality
  slide.addShape(pres.ShapeType.roundRect, {
    x: 6.9, y: 1.6, w: 5.7, h: 5.2, rectRadius: 0.12, fill: { color: TEAL }, line: { type: "none" }
  });
  slide.addText("The reality in production", { x: 7.2, y: 1.85, w: 5.1, h: 0.5, fontFace: "Cambria", fontSize: 18, bold: true, color: NAVY, isTextBox: true, margin: 0 });
  slide.addText(
    [
      { text: "Agent handles discovery + mapping", options: { bullet: true, breakLine: true } },
      { text: "Agent translates code + runs validation", options: { bullet: true, breakLine: true } },
      { text: "Human approves cutover, every time", options: { bullet: true, breakLine: true } },
      { text: "2–4x faster — in the safe phases", options: { bullet: true, breakLine: false } },
    ],
    { x: 7.2, y: 2.5, w: 5.1, h: 3.8, fontFace: "Calibri", fontSize: 16, color: NAVY, isTextBox: true, margin: 0, paraSpaceAfter: 14 }
  );

  slide.addNotes("So what's the pitch versus the reality? The pitch is: the agent connects to production, runs the whole migration, no human needed, fire and forget. The reality, based on how this is actually working in production teams, is different. Agents handle discovery, schema mapping, code translation, and validation. But a human still approves the cutover — the moment the new database actually goes live. That's the step you can't easily undo, so it stays a human call. And in that safe zone, agents really are fast — two to four times faster on the phases that don't touch live data.");
}

// ---------- Slide 4: The two incidents (stat callouts) ----------
{
  const slide = pres.addSlide();
  slide.background = { color: WHITE };
  slide.addText("When the human-approval gate goes missing", {
    x: 0.6, y: 0.45, w: 12, h: 0.8, fontFace: "Cambria", fontSize: 26, bold: true, color: NAVY, isTextBox: true, margin: 0
  });

  // Incident 1
  slide.addShape(pres.ShapeType.roundRect, {
    x: 0.7, y: 1.6, w: 5.7, h: 5.2, rectRadius: 0.12, fill: { color: "F4F7F8" }, line: { color: ICE, width: 1 }
  });
  slide.addText("9 seconds", { x: 1.0, y: 1.85, w: 5.1, h: 1.0, fontFace: "Cambria", fontSize: 44, bold: true, color: NAVY, isTextBox: true, margin: 0 });
  slide.addText("PocketOS, April 2026", { x: 1.0, y: 2.75, w: 5.1, h: 0.45, fontFace: "Calibri", fontSize: 14, bold: true, color: TEAL, isTextBox: true, margin: 0 });
  slide.addText("A coding agent hit a credential mismatch, found an over-permissioned API token, and deleted the production database and every backup in the same volume. Most recent backup: 3 months old.", {
    x: 1.0, y: 3.3, w: 5.1, h: 3.2, fontFace: "Calibri", fontSize: 14.5, color: SLATE, isTextBox: true, margin: 0
  });

  // Incident 2
  slide.addShape(pres.ShapeType.roundRect, {
    x: 6.9, y: 1.6, w: 5.7, h: 5.2, rectRadius: 0.12, fill: { color: "F4F7F8" }, line: { color: ICE, width: 1 }
  });
  slide.addText("Every table", { x: 7.2, y: 1.85, w: 5.1, h: 1.0, fontFace: "Cambria", fontSize: 44, bold: true, color: NAVY, isTextBox: true, margin: 0 });
  slide.addText("Supabase, August 2026", { x: 7.2, y: 2.75, w: 5.1, h: 0.45, fontFace: "Calibri", fontSize: 14, bold: true, color: TEAL, isTextBox: true, margin: 0 });
  slide.addText("An agent ran a Prisma migration flag pointed at the production URL instead of a disposable test database. Prisma reset the shadow database first — against production. Every table was dropped.", {
    x: 7.2, y: 3.3, w: 5.1, h: 3.2, fontFace: "Calibri", fontSize: 14.5, color: SLATE, isTextBox: true, margin: 0
  });

  slide.addNotes("Here's why this distinction matters so much. Two real incidents in 2026. First: PocketOS, a car rental SaaS platform. An agent hit a credential mismatch, found an API token with way more access than it needed, and deleted the production database plus every backup — because the backups lived in the same storage volume. Nine seconds, gone. Second incident: a developer connected an agent to a live Supabase database and asked it to fix some issues. The agent ran a migration command with a flag pointed at production instead of a test database. Every single table got dropped. In both cases, the only thing telling the agent not to do this was a system prompt — and a system prompt is not a security control.");
}

// ---------- Slide 5: Key takeaways ----------
{
  const slide = pres.addSlide();
  slide.background = { color: NAVY };
  slide.addText("Key takeaways", {
    x: 0.6, y: 0.5, w: 12, h: 0.8, fontFace: "Cambria", fontSize: 30, bold: true, color: WHITE, isTextBox: true, margin: 0
  });

  const items = [
    ["1", "Agents do discovery, mapping, translation, and validation — not cutover."],
    ["2", "None of the agent's safe tasks require standing write access to production."],
    ["3", "Scope every credential; put a hard, non-bypassable gate on destructive operations."],
    ["4", "Keep backups outside the blast radius of the data they protect."],
  ];

  let y = 1.7;
  items.forEach(([num, text]) => {
    slide.addShape(pres.ShapeType.ellipse, {
      x: 0.8, y: y, w: 0.6, h: 0.6, fill: { color: TEAL }, line: { type: "none" }
    });
    slide.addText(num, { x: 0.8, y: y, w: 0.6, h: 0.6, fontFace: "Cambria", fontSize: 20, bold: true, color: NAVY, align: "center", valign: "middle", isTextBox: true, margin: 0 });
    slide.addText(text, { x: 1.7, y: y - 0.05, w: 10.6, h: 0.7, fontFace: "Calibri", fontSize: 17, color: ICE, valign: "middle", isTextBox: true, margin: 0 });
    y += 1.15;
  });

  slide.addNotes("Let's boil this down to four takeaways. One: agents are great at discovery, mapping, translation, and validation — not at deciding when to flip the switch to production. Two: none of those safe tasks actually need standing write access to a live database. Three: scope every credential tightly, and put a real, enforced gate — not just a polite instruction — on anything destructive. And four: keep your backups somewhere an agent, or anyone else, can't wipe out alongside the primary data.");
}

// ---------- Slide 6: Closing / CTA ----------
{
  const slide = pres.addSlide();
  slide.background = { color: TEAL };
  slide.addShape(pres.ShapeType.ellipse, {
    x: 9.5, y: -2, w: 6, h: 6, fill: { color: NAVY, transparency: 88 }, line: { type: "none" }
  });
  slide.addText("Is your next migration\nscoping agent access on the fly?", {
    x: 0.8, y: 2.0, w: 11.6, h: 1.8, fontFace: "Cambria", fontSize: 32, bold: true, color: NAVY, isTextBox: true, margin: 0
  });
  slide.addText("Read the full breakdown at dataplatformadvisory.com", {
    x: 0.8, y: 4.1, w: 11.6, h: 0.6, fontFace: "Calibri", fontSize: 18, color: NAVY, isTextBox: true, margin: 0
  });
  slide.addText("Ivan Lima  ·  Data Platform Advisory", {
    x: 0.8, y: 6.6, w: 8, h: 0.5, fontFace: "Calibri", fontSize: 14, bold: true, color: NAVY, isTextBox: true, margin: 0
  });
  slide.addNotes("If your team is figuring out where AI agents actually belong in a database migration, and where the hard line needs to sit, that's exactly the kind of architecture review we do at Data Platform Advisory. Head to dataplatformadvisory.com for the full breakdown, and get in touch before your next migration project scopes agent access on the fly. Thanks for watching.");
}

pres.writeFile({ fileName: "/tmp/dbmod-work/video-scripts/agentic-ai-data-migration/script.pptx" }).then(() => {
  console.log("done");
});
