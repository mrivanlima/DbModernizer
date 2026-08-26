const pptxgen = require("pptxgenjs");

const NAVY = "0F2540";
const TEAL = "8FD3C7";
const ICE = "C9D9E3";
const WHITE = "FFFFFF";
const SLATE = "3A4A5A";

const HEAD = "Cambria";
const BODY = "Calibri";

let pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.3 x 7.5

// ---------- Slide 1: Title ----------
{
  let s = pres.addSlide();
  s.background = { color: NAVY };
  s.addShape("ellipse", { x: 10.8, y: -1.5, w: 5, h: 5, fill: { color: TEAL, transparency: 88 }, line: { type: "none" } });
  s.addText("The Database Modernization\nChecklist Every CTO Should\nRun Before Scaling AI", {
    x: 0.7, y: 1.5, w: 11.8, h: 3.0, fontFace: HEAD, fontSize: 40, bold: true, color: WHITE, margin: 0, align: "left", lineSpacingMultiple: 1.05
  });
  s.addText("Five database-layer checks before your next AI project starts", {
    x: 0.7, y: 4.55, w: 10.5, h: 0.6, fontFace: BODY, fontSize: 20, color: TEAL, margin: 0
  });
  s.addText("Ivan Lima · Data Platform Advisory", {
    x: 0.7, y: 6.6, w: 8, h: 0.5, fontFace: BODY, fontSize: 15, color: ICE, margin: 0
  });
  s.addNotes("Hey, I'm Ivan Lima with Data Platform Advisory. Today I want to walk you through a checklist — five things every CTO should verify at the database layer before greenlighting another AI project.");
}

// ---------- Slide 2: Hook / problem ----------
{
  let s = pres.addSlide();
  s.background = { color: WHITE };
  s.addText("The confidence-reality gap", {
    x: 0.6, y: 0.5, w: 11, h: 0.8, fontFace: HEAD, fontSize: 32, bold: true, color: NAVY, margin: 0
  });
  // two big stat callouts side by side
  s.addShape("roundRect", { x: 0.7, y: 1.7, w: 5.6, h: 4.6, rectRadius: 0.12, fill: { color: NAVY }, line: { type: "none" } });
  s.addText("87%", { x: 0.7, y: 2.1, w: 5.6, h: 1.6, fontFace: HEAD, fontSize: 72, bold: true, color: TEAL, align: "center", margin: 0 });
  s.addText("of leaders say they have\nthe infrastructure needed for AI", {
    x: 1.0, y: 3.8, w: 5.0, h: 1.3, fontFace: BODY, fontSize: 17, color: WHITE, align: "center", margin: 0
  });
  s.addText("Precisely, 2026 State of Data Integrity\nand AI Readiness", {
    x: 1.0, y: 5.6, w: 5.0, h: 0.6, fontFace: BODY, fontSize: 11, italic: true, color: ICE, align: "center", margin: 0
  });

  s.addShape("roundRect", { x: 6.6, y: 1.7, w: 5.6, h: 4.6, rectRadius: 0.12, fill: { color: SLATE }, line: { type: "none" } });
  s.addText("43%", { x: 6.6, y: 2.1, w: 5.6, h: 1.6, fontFace: HEAD, fontSize: 72, bold: true, color: TEAL, align: "center", margin: 0 });
  s.addText("call data readiness their\ntop barrier to AI alignment", {
    x: 6.9, y: 3.8, w: 5.0, h: 1.3, fontFace: BODY, fontSize: 17, color: WHITE, align: "center", margin: 0
  });
  s.addText("Same survey, same leaders —\ntwo different questions", {
    x: 6.9, y: 5.6, w: 5.0, h: 0.6, fontFace: BODY, fontSize: 11, italic: true, color: ICE, align: "center", margin: 0
  });

  s.addNotes("Here's the tension. 87% of leaders say they've got the AI infrastructure in place. But in that same survey, 43% name data readiness as their number one obstacle. Those aren't contradictory — they're answering two different questions. Having servers and a cloud account isn't the same as having a database an AI system can safely read from, write to, and be governed against.");
}

// ---------- Slide 3: Why it matters (cost of skipping) ----------
{
  let s = pres.addSlide();
  s.background = { color: NAVY };
  s.addText("The cost of skipping this step", {
    x: 0.6, y: 0.5, w: 11, h: 0.8, fontFace: HEAD, fontSize: 32, bold: true, color: WHITE, margin: 0
  });

  const rows = [
    { pct: "60%", label: "of AI projects abandoned through 2026 for lack of AI-ready data", src: "Gartner" },
    { pct: "85%", label: "of failed AI projects trace back to poor data quality", src: "Gartner, 2025" },
    { pct: "80%", label: "overall AI project failure rate across 2,400+ enterprise initiatives", src: "RAND Corporation" },
  ];
  let y = 1.9;
  rows.forEach(r => {
    s.addShape("ellipse", { x: 0.8, y: y, w: 1.5, h: 1.5, fill: { color: TEAL, transparency: 10 }, line: { type: "none" } });
    s.addText(r.pct, { x: 0.8, y: y, w: 1.5, h: 1.5, fontFace: HEAD, fontSize: 26, bold: true, color: NAVY, align: "center", valign: "middle", margin: 0 });
    s.addText(r.label, { x: 2.6, y: y + 0.05, w: 8.3, h: 0.9, fontFace: BODY, fontSize: 18, color: WHITE, margin: 0, valign: "middle" });
    s.addText(r.src, { x: 2.6, y: y + 0.95, w: 8.3, h: 0.4, fontFace: BODY, fontSize: 12, italic: true, color: TEAL, margin: 0 });
    y += 1.7;
  });

  s.addNotes("This isn't a minor gap. Gartner projects that 60% of AI projects will be abandoned through 2026 specifically because they lack AI-ready data. Separately, they found 85% of failed AI projects trace back to poor data quality. And RAND's analysis of over 2,400 enterprise AI initiatives puts overall failure above 80%. None of that is a model problem — it's a foundation problem, and the foundation is the database.");
}

// ---------- Slide 4: The five checklist items ----------
{
  let s = pres.addSlide();
  s.background = { color: WHITE };
  s.addText("Five things to check first", {
    x: 0.6, y: 0.4, w: 11, h: 0.7, fontFace: HEAD, fontSize: 30, bold: true, color: NAVY, margin: 0
  });

  const items = [
    "Can an LLM actually understand your schema?",
    "Does access control know a person from an agent?",
    "Has backup/restore been tested under real load?",
    "Does every schema change have a rollback path?",
    "Who owns data quality — by name?",
  ];
  let y = 1.4;
  items.forEach((t, i) => {
    s.addShape("roundRect", { x: 0.7, y: y, w: 0.5, h: 0.5, rectRadius: 0.08, fill: { color: NAVY }, line: { type: "none" } });
    s.addText(String(i + 1), { x: 0.7, y: y, w: 0.5, h: 0.5, fontFace: HEAD, fontSize: 20, bold: true, color: TEAL, align: "center", valign: "middle", margin: 0 });
    s.addText(t, { x: 1.4, y: y - 0.02, w: 10.5, h: 0.6, fontFace: BODY, fontSize: 19, color: SLATE, valign: "middle", margin: 0 });
    y += 1.05;
  });

  s.addNotes("So here are the five things. One: can an LLM actually understand your schema, or is it full of undocumented columns only your senior DBA can decode? Two: does your access control tell the difference between a human and an AI agent? Three: have you actually tested backup and restore under real load, recently? Four: does every schema change have a tested rollback path? And five — who owns data quality, by name? If it's everyone's job, it's no one's job.");
}

// ---------- Slide 5: Key takeaways ----------
{
  let s = pres.addSlide();
  s.background = { color: NAVY };
  s.addText("Key takeaways", {
    x: 0.6, y: 0.5, w: 11, h: 0.8, fontFace: HEAD, fontSize: 32, bold: true, color: WHITE, margin: 0
  });

  const bullets = [
    { t: "The 87%-vs-43% gap is real — infrastructure isn't the same as data readiness.", bold: "87%-vs-43%" },
    { t: "Governance programs report 71% high data trust, vs. 50% without one." },
    { t: "Run the checklist before you scope the AI project, not after it stalls." },
  ];

  let y = 1.9;
  bullets.forEach(b => {
    s.addShape("rect", { x: 0.8, y: y + 0.12, w: 0.18, h: 0.18, fill: { color: TEAL }, line: { type: "none" } });
    s.addText(b.t, { x: 1.25, y: y, w: 10.8, h: 0.9, fontFace: BODY, fontSize: 19, color: ICE, margin: 0, valign: "top" });
    y += 1.25;
  });

  s.addNotes("Three things to remember. First, that 87 versus 43 percent gap is real — having infrastructure isn't the same as having AI-ready data. Second, governance actually moves the needle: organizations with a formal governance program report 71% high data trust, versus just 50% without one. And third — run this checklist before you scope the AI project, not after it's already stalled in a pilot that never reaches production.");
}

// ---------- Slide 6: Closing / CTA ----------
{
  let s = pres.addSlide();
  s.background = { color: WHITE };
  s.addShape("roundRect", { x: 0.7, y: 1.3, w: 11.9, h: 4.6, rectRadius: 0.15, fill: { color: NAVY }, line: { type: "none" } });
  s.addText("Not sure your database can\nsupport what's coming next?", {
    x: 1.3, y: 2.0, w: 10.7, h: 1.6, fontFace: HEAD, fontSize: 30, bold: true, color: WHITE, margin: 0
  });
  s.addText("A short readiness review is a lot cheaper than a stalled AI project.", {
    x: 1.3, y: 3.5, w: 10.7, h: 0.6, fontFace: BODY, fontSize: 18, color: ICE, margin: 0
  });
  s.addText("dataplatformadvisory.com", {
    x: 1.3, y: 4.6, w: 8, h: 0.6, fontFace: BODY, fontSize: 20, bold: true, color: TEAL, margin: 0
  });
  s.addText("Ivan Lima · Data Platform Advisory", {
    x: 1.3, y: 5.2, w: 8, h: 0.5, fontFace: BODY, fontSize: 14, color: ICE, margin: 0
  });

  s.addNotes("If your team is scoping an AI initiative and you're not sure the database underneath it is ready, that's exactly the conversation worth having early. Head to dataplatformadvisory.com and get in touch — I'm Ivan Lima with Data Platform Advisory. Thanks for watching.");
}

pres.writeFile({ fileName: "script.pptx" }).then(() => console.log("done"));
