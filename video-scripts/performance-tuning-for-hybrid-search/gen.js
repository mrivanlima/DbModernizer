const pptxgen = require("pptxgenjs");

const NAVY = "0F2540";
const TEAL = "8FD3C7";
const ICE = "C9D9E3";
const WHITE = "FFFFFF";
const SLATE = "3A4A5A";

let pres = new pptxgen();
pres.layout = "LAYOUT_WIDE"; // 13.3 x 7.5

const HEAD = "Cambria";
const BODY = "Calibri";

// Slide 1: Title
let s1 = pres.addSlide();
s1.background = { color: NAVY };
s1.addText("Performance Tuning for Hybrid Search", {
  x: 0.8, y: 2.3, w: 11.7, h: 1.4, fontFace: HEAD, fontSize: 40, bold: true,
  color: WHITE, align: "left", isTextBox: true, margin: 0
});
s1.addText("When Vector and Keyword Search Compete for Resources", {
  x: 0.8, y: 3.6, w: 11.7, h: 0.7, fontFace: BODY, fontSize: 20,
  color: TEAL, align: "left", isTextBox: true, margin: 0
});
s1.addText("Ivan Lima  ·  Data Platform Advisory", {
  x: 0.8, y: 6.5, w: 8, h: 0.5, fontFace: BODY, fontSize: 15,
  color: ICE, align: "left", isTextBox: true, margin: 0
});
s1.addShape(pres.ShapeType.ellipse, { x: 10.6, y: 0.6, w: 2.2, h: 2.2, fill: { color: TEAL, transparency: 85 }, line: { type: "none" } });
s1.addNotes("Hey, I'm Ivan Lima with Data Platform Advisory. Today I want to talk about something that trips up a lot of teams building retrieval-augmented generation systems: performance tuning for hybrid search, specifically what happens when vector search and keyword search start competing for the same resources.");

// Slide 2: Hook/problem
let s2 = pres.addSlide();
s2.background = { color: WHITE };
s2.addText("The Problem", {
  x: 0.8, y: 0.5, w: 8, h: 0.8, fontFace: HEAD, fontSize: 32, bold: true, color: NAVY, isTextBox: true, margin: 0
});
s2.addText("Hybrid search runs two expensive queries per request — not one.", {
  x: 0.8, y: 1.4, w: 11.5, h: 0.6, fontFace: BODY, fontSize: 18, color: SLATE, isTextBox: true, margin: 0
});

// two boxes
s2.addShape(pres.ShapeType.roundRect, { x: 0.8, y: 2.4, w: 5.5, h: 3.6, rectRadius: 0.12, fill: { color: NAVY }, line: { type: "none" } });
s2.addText("Vector Search (HNSW)", { x: 1.1, y: 2.65, w: 5, h: 0.5, fontFace: HEAD, fontSize: 18, bold: true, color: TEAL, isTextBox: true, margin: 0 });
s2.addText([
  { text: "Graph traversal, RAM-resident", options: { bullet: true, breakLine: true } },
  { text: "Memory- and CPU-bound", options: { bullet: true, breakLine: true } },
  { text: "Competes for buffer cache", options: { bullet: true } },
], { x: 1.1, y: 3.3, w: 4.9, h: 2.4, fontFace: BODY, fontSize: 14, color: ICE, isTextBox: true, margin: 0, paraSpaceAfter: 10 });

s2.addShape(pres.ShapeType.roundRect, { x: 6.9, y: 2.4, w: 5.6, h: 3.6, rectRadius: 0.12, fill: { color: SLATE }, line: { type: "none" } });
s2.addText("Keyword Search (BM25)", { x: 7.2, y: 2.65, w: 5, h: 0.5, fontFace: HEAD, fontSize: 18, bold: true, color: TEAL, isTextBox: true, margin: 0 });
s2.addText([
  { text: "Inverted index scan", options: { bullet: true, breakLine: true } },
  { text: "I/O- and worker-bound", options: { bullet: true, breakLine: true } },
  { text: "Competes for parallel workers", options: { bullet: true } },
], { x: 7.2, y: 3.3, w: 5.1, h: 2.4, fontFace: BODY, fontSize: 14, color: ICE, isTextBox: true, margin: 0, paraSpaceAfter: 10 });

s2.addText("Both share the same CPU, buffer cache, and connection pool.", {
  x: 0.8, y: 6.3, w: 11.5, h: 0.6, fontFace: BODY, fontSize: 15, italic: true, color: NAVY, isTextBox: true, margin: 0
});
s2.addNotes("Here's the core problem. Hybrid search combines vector similarity search with keyword search, usually BM25, to get better accuracy. Vector search traverses a graph structure called HNSW, and it wants to live in memory. Keyword search scans an inverted index and leans more on disk I/O and parallel workers. They look independent, but they're running on the same instance, fighting over the same CPU cores, the same buffer cache, and the same connection pool.");

// Slide 3: content - the accuracy stat
let s3 = pres.addSlide();
s3.background = { color: NAVY };
s3.addText("The Accuracy Payoff Isn't Free", {
  x: 0.8, y: 0.5, w: 11, h: 0.8, fontFace: HEAD, fontSize: 30, bold: true, color: WHITE, isTextBox: true, margin: 0
});
const stats = [
  { label: "Dense-only recall@10", value: "78%" },
  { label: "Sparse-only (BM25) recall@10", value: "65%" },
  { label: "Hybrid search recall@10", value: "91%" },
];
let sx = 0.8;
stats.forEach((st, i) => {
  s3.addShape(pres.ShapeType.roundRect, { x: sx, y: 2.2, w: 3.7, h: 3.2, rectRadius: 0.12, fill: { color: i === 2 ? TEAL : "1B3A5C" }, line: { type: "none" } });
  s3.addText(st.value, { x: sx, y: 2.6, w: 3.7, h: 1.2, align: "center", fontFace: HEAD, fontSize: 46, bold: true, color: i === 2 ? NAVY : TEAL, isTextBox: true, margin: 0 });
  s3.addText(st.label, { x: sx + 0.2, y: 4.0, w: 3.3, h: 1.0, align: "center", fontFace: BODY, fontSize: 14, color: i === 2 ? NAVY : ICE, isTextBox: true, margin: 0 });
  sx += 4.0;
});
s3.addText("Hybrid search's recall gain requires running two resource-hungry retrievers concurrently, on every request.", {
  x: 0.8, y: 5.8, w: 11.5, h: 0.8, fontFace: BODY, fontSize: 15, color: ICE, isTextBox: true, margin: 0
});
s3.addNotes("The numbers explain why teams adopt hybrid search in the first place. Dense vector-only retrieval gets you about 78% recall at 10. Keyword-only BM25 gets you about 65%. But combine them with hybrid search, and recall jumps to 91%. That's a big jump in accuracy. But it means every single request is now running two expensive retrieval operations at once, not one -- and that's where the resource contention comes from.");

// Slide 4: content - RRF and latency budget
let s4 = pres.addSlide();
s4.background = { color: WHITE };
s4.addText("Where the Latency Budget Actually Goes", {
  x: 0.8, y: 0.5, w: 11.5, h: 0.8, fontFace: HEAD, fontSize: 30, bold: true, color: NAVY, isTextBox: true, margin: 0
});
s4.addShape(pres.ShapeType.roundRect, { x: 0.8, y: 1.7, w: 11.6, h: 1.3, rectRadius: 0.1, fill: { color: TEAL }, line: { type: "none" } });
s4.addText("Reciprocal Rank Fusion (RRF) is cheap — just addition across ranked candidates", {
  x: 1.1, y: 1.95, w: 11, h: 0.8, fontFace: BODY, fontSize: 17, bold: true, color: NAVY, isTextBox: true, margin: 0
});
s4.addText([
  { text: "The two retrievals feeding RRF are the actual bottleneck", options: { bullet: true, breakLine: true } },
  { text: "Isolated benchmarks mislead: 8ms vector + 12ms keyword look fine measured separately", options: { bullet: true, breakLine: true } },
  { text: "Run 200 of each concurrently — both numbers move, often nonlinearly", options: { bullet: true, breakLine: true } },
  { text: "Load-test both retrievers together, at real QPS, before trusting any single-path benchmark", options: { bullet: true } },
], { x: 0.8, y: 3.3, w: 11.4, h: 3.6, fontFace: BODY, fontSize: 16, color: SLATE, isTextBox: true, margin: 0, paraSpaceAfter: 16 });
s4.addNotes("So if fusion itself is cheap, where does the latency actually go? Reciprocal rank fusion, or RRF, just merges two already-ranked lists by position. It's basically addition. It's never the bottleneck. The real cost is the two retrieval queries feeding it. And here's the trap: if you benchmark them separately, an 8-millisecond vector query and a 12-millisecond keyword query both look totally fine. But run 200 of each at the same time against the same instance, and both numbers move, often in ways that aren't linear, because now they're fighting for the same CPU and memory. Always load test both retrievers running together, not one at a time.");

// Slide 5: key takeaways
let s5 = pres.addSlide();
s5.background = { color: NAVY };
s5.addText("Key Takeaways", {
  x: 0.8, y: 0.5, w: 8, h: 0.8, fontFace: HEAD, fontSize: 32, bold: true, color: WHITE, isTextBox: true, margin: 0
});
const takeaways = [
  "Hybrid search's accuracy gain costs two resource-hungry queries per request",
  "Vector and keyword search have different resource profiles — tune them separately",
  "Contention shows up under concurrency, not in isolated single-query benchmarks",
  "RRF is cheap; the retrieval feeding it isn't — that's where the budget goes",
  "Cap connection pools and parallel workers per retriever, don't share one unbounded pool",
];
let ty = 1.7;
takeaways.forEach((t, i) => {
  s5.addShape(pres.ShapeType.ellipse, { x: 0.8, y: ty, w: 0.5, h: 0.5, fill: { color: TEAL }, line: { type: "none" } });
  s5.addText(String(i + 1), { x: 0.8, y: ty, w: 0.5, h: 0.5, align: "center", valign: "middle", fontFace: HEAD, fontSize: 16, bold: true, color: NAVY, isTextBox: true, margin: 0 });
  s5.addText(t, { x: 1.5, y: ty - 0.05, w: 10.8, h: 0.6, fontFace: BODY, fontSize: 16, color: ICE, isTextBox: true, margin: 0, valign: "middle" });
  ty += 1.0;
});
s5.addNotes("Let's wrap up the key points. Hybrid search's accuracy gain isn't free -- it costs two resource-hungry queries per request. Vector and keyword search have different resource profiles, so tune them separately. Contention only shows up when you test both retrievers under real concurrency, not in isolated benchmarks. RRF itself is cheap; the retrieval feeding it is where your latency budget actually goes. And finally, cap your connection pools and parallel workers per retriever instead of sharing one unbounded pool between them.");

// Slide 6: closing/CTA
let s6 = pres.addSlide();
s6.background = { color: WHITE };
s6.addShape(pres.ShapeType.roundRect, { x: 0, y: 0, w: 13.33, h: 7.5, rectRadius: 0, fill: { color: NAVY }, line: { type: "none" } });
s6.addText("Building Retrieval Infrastructure?", {
  x: 0.8, y: 2.2, w: 11.7, h: 1.0, fontFace: HEAD, fontSize: 34, bold: true, color: WHITE, isTextBox: true, margin: 0
});
s6.addText("Let's find where contention will show up in your architecture — before it shows up in production.", {
  x: 0.8, y: 3.2, w: 10.5, h: 0.8, fontFace: BODY, fontSize: 17, color: ICE, isTextBox: true, margin: 0
});
s6.addShape(pres.ShapeType.roundRect, { x: 0.8, y: 4.4, w: 3.4, h: 0.7, rectRadius: 0.1, fill: { color: TEAL }, line: { type: "none" } });
s6.addText("dataplatformadvisory.com", { x: 0.8, y: 4.4, w: 3.4, h: 0.7, align: "center", valign: "middle", fontFace: BODY, fontSize: 15, bold: true, color: NAVY, isTextBox: true, margin: 0 });
s6.addText("Ivan Lima  ·  Data Platform Advisory", {
  x: 0.8, y: 6.6, w: 8, h: 0.5, fontFace: BODY, fontSize: 14, color: ICE, isTextBox: true, margin: 0
});
s6.addNotes("If your retrieval pipeline is still growing, this kind of contention compounds over time. It's invisible in a small proof of concept, and very visible once you're at real production scale with concurrent users. If you want a second set of eyes on where this is likely to hit your architecture, head to dataplatformadvisory.com and get in touch. Thanks for watching.");

pres.writeFile({ fileName: "/tmp/dbmod-work2/video-scripts/performance-tuning-for-hybrid-search/script.pptx" }).then(() => console.log("done"));
