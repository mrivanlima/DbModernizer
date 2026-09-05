const pptxgen = require("pptxgenjs");

const NAVY = "0F2540";
const TEAL = "8FD3C7";
const ICE = "C9D9E3";
const WHITE = "FFFFFF";
const SLATE = "3A4A5A";

const pres = new pptxgen();
pres.layout = "LAYOUT_WIDE";

function baseSlide(bg) {
  const s = pres.addSlide();
  s.background = { color: bg };
  return s;
}

// Slide 1: Title
{
  const s = baseSlide(NAVY);
  s.addText("A CTO's Guide to", {
    x: 0.8, y: 1.6, w: 11.7, h: 0.8, fontFace: "Cambria", fontSize: 32, color: WHITE, bold: true, isTextBox: true, margin: 0,
  });
  s.addText("Evaluating RAG Systems Before You Ship", {
    x: 0.8, y: 2.3, w: 11.7, h: 1.2, fontFace: "Cambria", fontSize: 40, color: TEAL, bold: true, isTextBox: true, margin: 0,
  });
  s.addShape("ellipse", { x: 0.8, y: 3.9, w: 0.12, h: 0.12, fill: { color: TEAL } });
  s.addText("Ivan Lima  ·  Data Platform Advisory", {
    x: 1.05, y: 3.75, w: 8, h: 0.5, fontFace: "Calibri", fontSize: 18, color: ICE, isTextBox: true, margin: 0,
  });
  s.addNotes("Hey, I'm Ivan Lima with Data Platform Advisory. If you're a CTO thinking about shipping a RAG system, this one's for you -- a practical guide to evaluating it before it goes live.");
}

// Slide 2: Hook/problem
{
  const s = baseSlide(WHITE);
  s.addText("The Problem", {
    x: 0.8, y: 0.6, w: 8, h: 0.7, fontFace: "Cambria", fontSize: 30, color: NAVY, bold: true, isTextBox: true, margin: 0,
  });
  s.addShape("roundRect", { x: 0.8, y: 1.6, w: 11.7, h: 2.1, rectRadius: 0.12, fill: { color: "F4F7F8" }, line: { color: ICE, width: 1 } });
  s.addText("Most teams evaluate a RAG system by reading a few answers and asking:", {
    x: 1.2, y: 1.85, w: 11, h: 0.5, fontFace: "Calibri", fontSize: 18, color: SLATE, isTextBox: true, margin: 0,
  });
  s.addText('"Does this sound right?"', {
    x: 1.2, y: 2.35, w: 11, h: 0.8, fontFace: "Cambria", fontSize: 30, color: NAVY, italic: true, bold: true, isTextBox: true, margin: 0,
  });
  s.addText("That's a spot-check, not an evaluation -- and it misses exactly where RAG breaks.", {
    x: 1.2, y: 3.1, w: 11, h: 0.5, fontFace: "Calibri", fontSize: 16, color: SLATE, isTextBox: true, margin: 0,
  });

  // stat callouts row
  const stats = [
    { n: "50%", l: "of GenAI projects abandoned\nafter proof-of-concept (Gartner)" },
    { n: "95%", l: "of orgs saw no P&L return\non GenAI pilots (MIT NANDA)" },
  ];
  let x = 0.8;
  stats.forEach((st) => {
    s.addShape("roundRect", { x, y: 4.1, w: 5.6, h: 1.5, rectRadius: 0.1, fill: { color: NAVY } });
    s.addText(st.n, { x: x + 0.3, y: 4.25, w: 2, h: 0.9, fontFace: "Cambria", fontSize: 44, color: TEAL, bold: true, isTextBox: true, margin: 0 });
    s.addText(st.l, { x: x + 2.1, y: 4.35, w: 3.3, h: 1.0, fontFace: "Calibri", fontSize: 12, color: WHITE, isTextBox: true, margin: 0 });
    x += 6.1;
  });
  s.addNotes("Here's the problem: most RAG demos get judged by a human reading a handful of answers and nodding along. That's not an evaluation. And the stakes are real -- Gartner says half of GenAI projects get abandoned after the pilot stage, and MIT found ninety-five percent of orgs see zero financial return. A lot of that traces straight back to RAG systems that were never properly evaluated.");
}

// Slide 3: Four checkpoints (icon rows)
{
  const s = baseSlide(WHITE);
  s.addText("Four Checkpoints, Not One", {
    x: 0.8, y: 0.5, w: 11, h: 0.7, fontFace: "Cambria", fontSize: 28, color: NAVY, bold: true, isTextBox: true, margin: 0,
  });
  const items = [
    ["1", "Retrieval Quality", "Recall@k, precision@k, NDCG -- did it find the right documents at all?"],
    ["2", "Faithfulness", "Is every claim in the answer traceable back to the retrieved context?"],
    ["3", "Hallucination Rate", "Did it invent a fact, name, or number that appears nowhere in the source?"],
    ["4", "Production Drift", "Does quality hold up after launch, as embeddings and queries shift?"],
  ];
  let y = 1.5;
  items.forEach(([num, title, desc]) => {
    s.addShape("ellipse", { x: 0.8, y, w: 0.7, h: 0.7, fill: { color: NAVY } });
    s.addText(num, { x: 0.8, y, w: 0.7, h: 0.7, align: "center", valign: "middle", fontFace: "Cambria", fontSize: 24, color: TEAL, bold: true, isTextBox: true, margin: 0 });
    s.addText(title, { x: 1.8, y: y - 0.05, w: 4, h: 0.5, fontFace: "Calibri", fontSize: 18, bold: true, color: NAVY, isTextBox: true, margin: 0 });
    s.addText(desc, { x: 1.8, y: y + 0.4, w: 10.2, h: 0.5, fontFace: "Calibri", fontSize: 13, color: SLATE, isTextBox: true, margin: 0 });
    y += 1.15;
  });
  s.addNotes("So instead of one big yes-or-no question, break it into four. First, retrieval quality -- did the system even find the right documents. Second, faithfulness -- does the answer actually stick to what it retrieved. Third, hallucination rate -- did it make something up that's nowhere in your source material. And fourth, production drift -- does it stay accurate weeks after launch, not just on demo day.");
}

// Slide 4: Why it degrades (two column)
{
  const s = baseSlide(NAVY);
  s.addText("Why It Degrades After Launch", {
    x: 0.8, y: 0.5, w: 11, h: 0.7, fontFace: "Cambria", fontSize: 28, color: WHITE, bold: true, isTextBox: true, margin: 0,
  });
  const left = [
    ["Embedding drift", "New queries and old documents fall out of a comparable vector space."],
    ["Index staleness", "Source docs change; the vector index doesn't get refreshed to match."],
  ];
  const right = [
    ["Query-distribution shift", "Real users phrase things differently than your test queries."],
    ["Corpus poisoning", "Unvetted content gets ingested and treated as ground truth."],
  ];
  function col(items, x) {
    let y = 1.7;
    items.forEach(([t, d]) => {
      s.addShape("roundRect", { x, y, w: 5.5, h: 1.7, rectRadius: 0.1, fill: { color: "132C4A" } });
      s.addText(t, { x: x + 0.3, y: y + 0.2, w: 5, h: 0.5, fontFace: "Calibri", fontSize: 17, bold: true, color: TEAL, isTextBox: true, margin: 0 });
      s.addText(d, { x: x + 0.3, y: y + 0.7, w: 5, h: 0.9, fontFace: "Calibri", fontSize: 13, color: ICE, isTextBox: true, margin: 0 });
      y += 1.95;
    });
  }
  col(left, 0.8);
  col(right, 6.6);
  s.addNotes("None of this throws an error. A RAG system that passed every test on launch day can quietly get worse over time -- embeddings drift, indexes go stale, real users ask questions differently than your test set, and if you're ingesting outside content, bad documents can sneak into the corpus and get treated as fact. The only way to catch this is to keep running your evaluations on a schedule, not just once before ship.");
}

// Slide 5: Key takeaways
{
  const s = baseSlide(WHITE);
  s.addText("Key Takeaways", {
    x: 0.8, y: 0.5, w: 11, h: 0.7, fontFace: "Cambria", fontSize: 28, color: NAVY, bold: true, isTextBox: true, margin: 0,
  });
  const bullets = [
    "Evaluate retrieval and generation separately.",
    "Track recall@k, precision@k, and NDCG before judging the generated text.",
    "Faithfulness and hallucination are different failure modes -- test both.",
    "Run evaluations on a recurring schedule, not just once before launch.",
    "RAG quality is a data-platform problem, not a prompt-tuning problem.",
  ];
  s.addShape("roundRect", { x: 0.8, y: 1.5, w: 11.7, h: 4.6, rectRadius: 0.12, fill: { color: "F4F7F8" }, line: { color: ICE, width: 1 } });
  const items = bullets.map((b, i) => ({
    text: b,
    options: { bullet: true, breakLine: i !== bullets.length - 1, paraSpaceAfter: 18, fontFace: "Calibri", fontSize: 18, color: SLATE },
  }));
  s.addText(items, { x: 1.3, y: 1.85, w: 10.7, h: 4.0, isTextBox: true, margin: 0 });
  s.addNotes("So here's the short version. Evaluate retrieval and generation as two separate problems. Track recall, precision, and NDCG before you even look at the generated text. Treat faithfulness and hallucination as two different numbers on your dashboard. Keep re-running your evaluations after launch, not just before it. And remember -- RAG quality traces back to your data platform, not your prompt.");
}

// Slide 6: CTA
{
  const s = baseSlide(NAVY);
  s.addText("Is Your Data Platform", {
    x: 0.8, y: 1.5, w: 11.7, h: 0.8, fontFace: "Cambria", fontSize: 32, color: WHITE, bold: true, isTextBox: true, margin: 0,
  });
  s.addText("Ready for RAG?", {
    x: 0.8, y: 2.2, w: 11.7, h: 0.9, fontFace: "Cambria", fontSize: 36, color: TEAL, bold: true, isTextBox: true, margin: 0,
  });
  s.addShape("roundRect", { x: 0.8, y: 3.4, w: 5.4, h: 1.3, rectRadius: 0.1, fill: { color: "132C4A" } });
  s.addText("dataplatformadvisory.com", { x: 1.1, y: 3.7, w: 5, h: 0.7, fontFace: "Calibri", fontSize: 18, color: TEAL, bold: true, isTextBox: true, margin: 0 });
  s.addText("Ivan Lima  ·  Data Platform Advisory", {
    x: 0.8, y: 5.0, w: 8, h: 0.5, fontFace: "Calibri", fontSize: 16, color: ICE, isTextBox: true, margin: 0,
  });
  s.addNotes("If your team is trying to figure out whether your database and data platform are actually ready to support RAG and other AI workloads, that's exactly what we help with at Data Platform Advisory. Head to dataplatformadvisory.com to get in touch. Thanks for watching.");
}

pres.writeFile({ fileName: "script.pptx" }).then(() => console.log("done"));
