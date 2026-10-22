"""Build the English AI handoff report from the current audit evidence.

Does not launch or modify the application. Existing contrast-samples.json contains
the approximate raster measurements produced during the original inspection.
"""
import base64
from html import escape
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REPO = '/Users/yaoyao/code/project/pic_review_edit'

issues = [
    {
        'id': 'F01', 'priority': 'P1', 'status': 'observed_in_live_ui',
        'title': 'White transport icons lose contrast against pale button surfaces',
        'affected_surface': 'Video / Live Photo transport: previous frame, play, next frame, range zoom, and mute.',
        'reproduction': ['Open a video or Live Photo in the editor.', 'Inspect the available circular transport buttons below the preview in both system appearances.'],
        'observation': 'Enabled circular controls have pale gray surfaces with white symbols. Representative screenshot colors are white on #D2D2D2, approximately 1.51:1. These are available controls, not the disabled Undo / Redo buttons.',
        'likely_cause': 'IconButton explicitly sets the symbol foreground to .primary. In the dark environment this resolves to a light foreground, while glassButton(.circle) produces a pale surface. The explicit label style appears to override the intended surface-aware foreground.',
        'source_locations': [('Sources/MediaWorkbenchApp/WorkbenchUI.swift',217), ('Sources/MediaWorkbenchApp/WorkbenchUI.swift',283), ('Sources/MediaWorkbenchApp/MediaTimeline.swift',65)],
        'recommended_change': 'First test removing the explicit foreground override for ordinary symbols so the native button style can choose its foreground. If custom styling remains necessary, define foreground and button surface as a pair. Verify active accent symbols separately. Do not apply a global white foreground.',
        'acceptance_criteria': ['Every enabled transport symbol is recognizable in normal, hover, pressed, and active states.', 'Target at least 3:1 for meaningful symbols against their actual button surfaces.', 'Check both system Light and Dark appearances and all IconButton call sites.'],
        'evidence': ['12-system-dark-audio.png'], 'detail_images': ['transport'], 'sample_ids': ['transport'],
    },
    {
        'id': 'F02', 'priority': 'P1', 'status': 'observed_in_live_ui',
        'title': 'Essential parameter and metadata labels are too dim on dark panels',
        'affected_surface': 'Simple / Full Color, Geometry, Audio, and Info panels; parameter names, units, and metadata field names.',
        'reproduction': ['Open a photo or video and expand basic adjustments.', 'Compare untouched parameter names with their numeric values.', 'Check Geometry position / angle controls, Audio volume, and Info metadata rows.'],
        'observation': 'Numeric values remain legible while the corresponding names become much darker. Approximate raster samples: parameter label 3.32:1; metadata field label 3.38:1. Meaningful units such as EV, degrees, and percent are even more subdued.',
        'likely_cause': 'ParameterRow uses .secondary whenever value == neutral. This visually conflates an unchanged, enabled parameter with an unavailable control. InfoPanel.row also uses .secondary, while the parameter suffix uses .tertiary.',
        'source_locations': [('Sources/MediaWorkbenchApp/WorkbenchUI.swift',72), ('Sources/MediaWorkbenchApp/WorkbenchUI.swift',88), ('Sources/MediaWorkbenchApp/InspectorView.swift',674)],
        'recommended_change': 'Give essential labels a guaranteed readable foreground on the actual panel surface. Express modified / unmodified state through a marker, weight, or other treatment that preserves text contrast. Keep meaningful units readable. Avoid fixing only individual call sites when ParameterRow is the shared cause.',
        'acceptance_criteria': ['Untouched enabled labels are readable before the user changes any value.', 'Check neutral, modified, and disabled states independently.', 'Target at least 4.5:1 for normal-size enabled text, including meaningful units.'],
        'evidence': ['03-basic-expanded.png','08-system-light-info.png','09-geometry.png','10-audio.png'],
        'detail_images': ['parameters','metadata','geometry'], 'sample_ids': ['parameter','metadata'],
    },
    {
        'id': 'F03', 'priority': 'P2', 'status': 'observed_in_live_ui',
        'title': 'Available presets and unselected tabs look unavailable',
        'affected_surface': 'Preset captions, Save Preset and Match Look entry points; inspector tabs, Simple / Full selector, and scope selector.',
        'reproduction': ['Open an ordinary photo and inspect the preset grid in Simple Color.', 'Compare the selected Original caption with other available preset captions.', 'Inspect available unselected inspector and scope tabs without hovering.'],
        'observation': 'The selected Original caption is clear; other available preset captions and entry points are much dimmer. The AI Look caption sample is approximately 3.34:1. Unselected segmented labels show a similar visual pattern, but each label was not individually measured.',
        'likely_cause': 'Preset captions use selected ? .primary : .secondary. GlassSegmentedControl also assigns Color.secondary to nonselected, nonhovered options. Available unselected and disabled appearances are insufficiently distinct.',
        'source_locations': [('Sources/MediaWorkbenchApp/InspectorView.swift',338), ('Sources/MediaWorkbenchApp/InspectorView.swift',298), ('Sources/MediaWorkbenchApp/GlassSegmentedControl.swift',54)],
        'recommended_change': 'Raise contrast for available unselected text. Use surface, stroke, or weight to distinguish the selected option. Reserve stronger dimming for genuinely disabled options. Keep the active, inactive-but-available, and disabled states distinct.',
        'acceptance_criteria': ['All available preset names and tabs are readable without hover.', 'Selected options remain identifiable.', 'Measure normal-size enabled text against a 4.5:1 design target.'],
        'evidence': ['13-photo-color.png','14-simple.png'], 'detail_images': ['presets'], 'sample_ids': ['preset'],
    },
    {
        'id': 'F04', 'priority': 'P2', 'status': 'observed_in_live_ui',
        'title': 'Learning groups, durations, and instructional hints are overly faint',
        'affected_surface': 'Learn lesson list and the sample-photo hint in the first lesson step.',
        'reproduction': ['Open Learn and inspect lesson group headings and duration labels.', 'Open the histogram lesson first step using the currently selected Live Photo.', 'Inspect the hint explaining that a user photo can replace the sample.'],
        'observation': 'Group headings and minute counts are difficult to read relative to lesson titles. Approximate samples: duration 2.28:1; sample-photo hint 2.33:1. The main lesson title and body are substantially clearer.',
        'likely_cause': 'Group headings, durations, and the sample-photo hint use .tertiary. InsightCard explanations also use .tertiary; that additional location was identified in source but not exhaustively expanded and reproduced in the live audit.',
        'source_locations': [('Sources/MediaWorkbenchApp/LearnViews.swift',397), ('Sources/MediaWorkbenchApp/LearnViews.swift',408), ('Sources/MediaWorkbenchApp/LessonPlayer.swift',71), ('Sources/MediaWorkbenchApp/LearnViews.swift',188)],
        'recommended_change': 'Keep explanatory text subordinate to titles without making it nearly disappear. Establish hierarchy through weight and spacing. Audit the related source-only InsightCard location during implementation.',
        'acceptance_criteria': ['Lesson groups, durations, and instructional hints remain readable on dark surfaces.', 'Expand relevant learning explanations during regression testing.', 'Target at least 4.5:1 for normal-size informational text.'],
        'evidence': ['04-learn.png','05-lesson.png'], 'detail_images': ['lessons','lesson-help'], 'sample_ids': ['duration','lesson-help'],
    },
    {
        'id': 'F05', 'priority': 'P2', 'status': 'observed_in_live_ui',
        'title': 'The project empty-state explanation blends into the sidebar',
        'affected_surface': 'Library sidebar, Projects section when no projects exist.',
        'reproduction': ['Use a library with no projects.', 'Inspect the sentence explaining the purpose of projects under the Projects heading.'],
        'observation': 'The introductory explanation is a meaningful sentence but appears as very dim small text. The approximate screenshot sample is 2.36:1.',
        'likely_cause': 'ProjectSidebar applies .caption and .tertiary to the full explanation. The actual translucent, wallpaper-tinted sidebar surface is not a fixed black background.',
        'source_locations': [('Sources/MediaWorkbenchApp/ProjectViews.swift',26)],
        'recommended_change': 'Promote this first-use explanation to a readable secondary-body treatment. Use spacing and line height to preserve hierarchy rather than further lowering foreground opacity.',
        'acceptance_criteria': ['The project purpose is readable at normal scale.', 'Check active and inactive windows and representative wallpaper backgrounds.', 'Target at least 4.5:1 for normal-size explanatory text.'],
        'evidence': ['01-browse-current.png'], 'detail_images': ['project-help'], 'sample_ids': ['project'],
    },
    {
        'id': 'F06', 'priority': 'P2', 'status': 'observed_readability_concern_platform_exceptions_apply',
        'title': 'White text on light accent-filled controls has limited contrast',
        'affected_surface': 'Export format / destination segments and primary actions; related lesson Next controls.',
        'reproduction': ['Open photo export with the current system accent.', 'Inspect the selected JPEG segment and primary action text.', 'Compare related accented controls in video export and the first lesson step.'],
        'observation': 'Representative selected JPEG colors are white on #6A99CE, approximately 2.97:1 in the screenshot. This is a readability improvement item. Native system-drawn controls have applicability exceptions; this observation alone is not a formal WCAG failure determination.',
        'likely_cause': 'WorkbenchTheme.accent is derived from the system accent once at launch, and SheetContent applies it to native controls. The final visible surface is additionally affected by platform rendering.',
        'source_locations': [('Sources/MediaWorkbenchApp/WorkbenchUI.swift',9), ('Sources/MediaWorkbenchApp/WorkbenchUI.swift',263), ('Sources/MediaWorkbenchApp/Sheets.swift',10), ('Sources/MediaWorkbenchApp/Sheets.swift',152)],
        'recommended_change': 'Verify the accent surface and the foreground chosen by each control as a pair. Define onAccent for app-controlled surfaces. If retaining white text, ensure a sufficiently dark fill. Prefer native adaptation for system-managed controls and avoid blindly overriding their foregrounds.',
        'acceptance_criteria': ['Inspect several system accents, selected segments, and primary buttons.', 'Target 4.5:1 for normal-size text where the app controls the color pair.', 'Evaluate native-control exceptions and actual platform behavior separately.'],
        'evidence': ['15-photo-export.png','06-export.png','05-lesson.png'], 'detail_images': ['export-controls'], 'sample_ids': ['export'],
    },
]

risks = [
    {
        'id':'R01','status':'source_confirmed_architecture_constraint_not_a_reproduced_light_theme_bug',
        'title':'There is no complete light application theme to validate yet',
        'source_locations':[('Sources/MediaWorkbenchApp/MediaWorkbenchApp.swift',22),('Sources/MediaWorkbenchApp/WorkbenchUI.swift',21)],
        'finding':'The root view forces .preferredColorScheme(.dark). Panel and canvas colors, white opacity treatments, stars, and selection tokens are largely fixed for dark surfaces. System Light appearance does not create a full light application theme.',
        'implementation_guardrail':'Do not remove the forced dark scheme as an isolated fix. If full light-mode support is in scope later, define paired surface, text, selection, onSelection, accent, and onAccent tokens together. Removing the scheme alone could let semantic dark text appear on fixed dark surfaces.',
    },
    {
        'id':'R02','status':'source_comment_lead_not_reproduced_in_current_live_ui',
        'title':'Near-black text may also occur in the snapshot capture path',
        'source_locations':[('scripts/make-site-screenshots.sh',84)],
        'finding':'The existing screenshot script documents that some window captures render secondary text on the translucent inspector as near-black. Its workaround renders the inspector separately and replaces the captured column. This comment is an investigation lead, not proof that the user-reported live issue is only a screenshot artifact.',
        'implementation_guardrail':'Compare the same state in a native window capture and DebugSnapshot output under system Light / Dark, active / inactive windows, and main / standalone panels. Do not treat replacing website screenshots as a fix for application contrast.',
    },
]

coverage = [
    ('01','Library and project empty state','Needs adjustment','Project explanation too dim; filenames and thumbnail badges are clear.',['01-browse-current.png']),
    ('02','Full Color and basic parameters','Priority adjustment','Parameter labels too dim; numeric values generally clear.',['03-basic-expanded.png']),
    ('03','Video / Live Photo transport','Priority adjustment','Pale surfaces and white symbols reduce enabled control legibility.',['12-system-dark-audio.png']),
    ('04','Photo Simple Color, presets, local-tool entry points','Needs adjustment','Preset and parameter labels dim; light local-tool buttons with dark text are clear.',['14-simple.png']),
    ('05','Geometry','Needs adjustment','Angle, retained area, and position labels dim; rotation buttons clear.',['09-geometry.png']),
    ('06','Audio','Needs adjustment','Volume label and units dim; Add Music button clear.',['10-audio.png']),
    ('07','Info','Needs adjustment','Metadata labels dim; values clear. Location area omitted from report images.',['08-system-light-info.png']),
    ('08','Learn and first lesson step','Needs adjustment','Groups, durations, and hint dim; main title and body clearer.',['04-learn.png','05-lesson.png']),
    ('09','Video and photo export','Partial adjustment','Main text generally readable; accent-selected text needs review.',['06-export.png','15-photo-export.png']),
    ('10','History popover','Sampled state generally clear','Title and current row readable; only the Original step existed, so multistep / redo rows were not tested.',['17-history.png']),
    ('11','System Light and Dark appearance','Application remains dark','Light: sampled Learn, Info, export. Dark: sampled Audio and Color. Original Auto appearance restored.',['07-system-light-learn.png','11-system-light-export.png','12-system-dark-audio.png']),
    ('12','Photos importer','Coverage blocked','Two observations remained on a loading indicator. Excluded as completed-screen evidence; no conclusion on grid or preview contrast.',['16-photos-import.png']),
]

report = {
    'title':'Lucet — Text and Surface Contrast Audit', 'language':'en', 'date':'2026-10-18',
    'repository_root':REPO, 'source_branch':'improve-workbench',
    'source_commit':'64c6336178e704c16a8a5ce9762fb96b7a458c25',
    'runtime_app':REPO+'/.build/MediaWorkbench.app', 'runtime_os':'macOS 27.0.1',
    'runtime_language':'Simplified Chinese',
    'version_limit':'The existing running app was not rebuilt. Binary-to-commit equivalence was not independently established; reproduce each item in a fresh build before patching.',
    'requested_scope':'Audit and report only. No application source changes, commits, pushes, or publication were performed.',
    'main_conclusion':'Observed problems include pale-surface white icons and overly dim gray text on dark panels. Pure black text on a dark surface was not stably reproduced in this live inspection.',
    'evidence_method':'Current-run native application captures, visually inspected; report detail images are unmodified crops. Samples are approximate screenshot estimates, not resolved-color compliance measurements.',
    'measurement_file':'contrast-samples.json',
    'design_targets':{'normal_text':4.5,'meaningful_icons':3.0,'caveat':'Disabled, decorative, and fully system-managed controls require applicability checks. This is not a complete accessibility certification.'},
    'issues':issues,'risks':risks,
    'do_not_change_blindly':[
        'LearnViews.swift:125–126 explicitly pairs black selected-topic text with an 85%-white capsule. Source inspected; that settings section was not expanded in the live capture.',
        'LessonScenes.swift:49 chooses black text on brighter grayscale cells. Not every frame or course state was inspected.',
        'Native live captures show readable dark text on pale Auto, rotation, and local-tool buttons. Preserve valid light-surface pairs.',
    ],
    'coverage':[dict(step=n,surface=title,health=status,observation=note,screenshots=files) for n,title,status,note,files in coverage],
    'not_covered':['macOS 15 / 26 runtime behavior','English application UI','Other system accent colors','Increase Contrast / Reduce Transparency','Every modal, error, empty, hover, pressed, and disabled state','All lesson steps','Side-by-side culling and collage','Loaded Photos import grid and preview','Local adjustment layer editing','All expanded learning insights'],
    'suggested_fix_order':['F01: shared IconButton foreground / surface pairing','F02 and F03: enabled label and tab contrast','F04 and F05: informational text hierarchy','F06 and R02: accent control review and capture-path comparison'],
    'handoff_instructions':[
        'Read the referenced source and reproduce the current UI before changing behavior.',
        'Keep this pass scoped to contrast and state clarity; preserve layout, copy, image processing, and data.',
        'Prefer shared fixes and paired color roles over scattered literal white / black replacements.',
        'Do not infer full light-theme support from system appearance switching.',
        'Validate with fresh live captures and resolved colors; do not hide real UI issues with composited marketing screenshots.',
        'Report confirmed fixes separately from source-only risks and remaining coverage gaps.',
    ],
}
(ROOT/'audit.json').write_text(json.dumps(report,ensure_ascii=False,indent=2)+'\n')

def image(name):
    data=base64.b64encode((ROOT/'details'/(name+'.png')).read_bytes()).decode()
    return f'<figure><img alt="{escape(name)} — current-run UI crop" src="data:image/png;base64,{data}"><figcaption>Current-run UI crop · {escape(name)}</figcaption></figure>'

def source_links(locations):
    return ''.join(f'<li><code>{escape(REPO+"/"+p)}:{line}</code></li>' for p,line in locations)

def bullets(items):
    return '<ul>'+''.join('<li>'+escape(x)+'</li>' for x in items)+'</ul>'

issue_rows=''.join(f'<tr><td><a href="#{x["id"]}">{x["id"]}</a></td><td><span class="badge {x["priority"].lower()}">{x["priority"]}</span></td><td>{escape(x["title"])}</td></tr>' for x in issues)
issue_sections=''
for x in issues:
    extra=''
    if len(x['detail_images'])>1:
        extra='<details><summary>Additional screenshot evidence</summary>'+''.join(image(n) for n in x['detail_images'][1:])+'</details>'
    issue_sections+=f'''<article id="{x['id']}" class="finding"><div class="eyebrow"><span class="badge {x['priority'].lower()}">{x['priority']}</span> {x['id']} · OBSERVED IN LIVE UI</div><h2>{escape(x['title'])}</h2><p class="muted">{escape(x['affected_surface'])}</p><div class="columns"><div>{image(x['detail_images'][0])}</div><div><h3>Observed behavior</h3><p>{escape(x['observation'])}</p><h3>Likely implementation cause</h3><p>{escape(x['likely_cause'])}</p><h3>Recommended change</h3><p>{escape(x['recommended_change'])}</p><h3>Acceptance criteria</h3>{bullets(x['acceptance_criteria'])}</div></div><details><summary>Reproduction and source locations</summary>{bullets(x['reproduction'])}<ul class="code-list">{source_links(x['source_locations'])}</ul><p class="muted">Original captures: {escape(', '.join(x['evidence']))}. Measurement IDs: {escape(', '.join(x['sample_ids']))}.</p></details>{extra}</article>'''

risk_sections=''.join(f'<h3><span class="badge risk">{x["id"]}</span> {escape(x["title"])}</h3><p>{escape(x["finding"])}</p><p><strong>Implementation guardrail:</strong> {escape(x["implementation_guardrail"])}</p><ul class="code-list">{source_links(x["source_locations"])}</ul>' for x in risks)
coverage_rows=''.join(f'<tr><td>{n}</td><td>{escape(title)}</td><td>{escape(status)}</td><td>{escape(note)}<small>{escape(", ".join(files))}</small></td></tr>' for n,title,status,note,files in coverage)

css='''*{box-sizing:border-box}html{scroll-behavior:smooth}body{margin:0;background:#fff;color:#20211e;font:16px/1.8 -apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif}header,main,footer{width:min(1180px,calc(100% - 64px));margin:auto}header{padding:60px 0 38px;border-bottom:1px solid #e5e6df}h1{font-size:clamp(32px,4vw,49px);line-height:1.15;letter-spacing:-.035em;margin:20px 0}h2{font-size:25px;line-height:1.35;margin:17px 0}h3{font-size:15px;line-height:1.6;margin:24px 0 7px}p{margin:0 0 16px}a{color:#49624d;text-underline-offset:4px}.eyebrow{font-size:12px;letter-spacing:.08em;color:#60635d;font-weight:600}.lead{font-size:19px;max-width:900px}.muted,figcaption,small{color:#61635d}.muted{font-size:14px}.stats{display:grid;grid-template-columns:repeat(4,1fr);gap:24px;border-top:1px solid #e5e6df;margin-top:28px;padding-top:24px}.stats b{display:block;font-size:36px;line-height:1.3;font-weight:550}.stats span{font-size:13px;color:#61635d}nav{display:flex;gap:22px;flex-wrap:wrap;margin-top:28px;font-size:14px}.section,.finding{padding:44px 0;border-bottom:1px solid #e5e6df;scroll-margin-top:16px}.columns{display:grid;grid-template-columns:minmax(0,1fr) minmax(0,1fr);gap:38px;align-items:start;margin-top:24px}.columns h3:first-child{margin-top:0}.callout{background:#f7f8f4;border-left:3px solid #49624d;padding:17px 22px;margin:25px 0}.callout p:last-child{margin-bottom:0}.badge{display:inline-block;border:1px solid;border-radius:5px;font-size:12px;padding:2px 8px;line-height:1.8;font-weight:650;margin-right:8px}.p1{color:#8b3c2c;background:#fbf1ec;border-color:#e2c3b9}.p2{color:#765d29;background:#fbf7ec;border-color:#ddd0ae}.risk{color:#52604f;background:#f4f7f1;border-color:#cbd6c6}figure{margin:0 0 20px}figure img{display:block;width:100%;height:auto;border:1px solid #deded8;border-radius:7px}figcaption{font-size:12px;margin-top:8px}details{background:#f7f8f4;border-radius:6px;padding:13px 17px;margin-top:20px}details figure{margin-top:20px;max-width:660px}summary{cursor:pointer;font-size:14px;font-weight:600}code{font:12px/1.7 ui-monospace,SFMono-Regular,Menlo,monospace;background:#f3f4ef;border-radius:3px;padding:2px 4px;overflow-wrap:anywhere}.code-list{font-size:12px;padding-left:20px}ul,ol{padding-left:22px}li{padding:4px 0}.scroll{overflow-x:auto}table{border-collapse:collapse;width:100%;font-size:14px;margin:24px 0}th,td{text-align:left;vertical-align:top;border-bottom:1px solid #e5e6df;padding:12px}th{font-size:12px;color:#61635d;background:#f7f8f4}td:first-child{white-space:nowrap}small{display:block;font-size:11px;margin-top:7px;overflow-wrap:anywhere}footer{padding:32px 0 60px;font-size:12px;color:#61635d}.print-button{font:inherit;font-size:13px;border:1px solid #c9cdc3;background:#fff;color:#20211e;padding:7px 13px;border-radius:5px;cursor:pointer}a:focus-visible,button:focus-visible,summary:focus-visible{outline:2px solid #49624d;outline-offset:4px}@media(max-width:800px){header,main,footer{width:calc(100% - 36px)}header{padding-top:35px}.columns{grid-template-columns:1fr;gap:24px}.stats{grid-template-columns:repeat(2,1fr)}h2{font-size:23px}}@media print{header,main,footer{width:100%}nav{display:none}body{font-size:11px}.finding{break-before:page}.columns{gap:22px}figure{break-inside:avoid}h2{font-size:20px}}'''

html=f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Lucet — Contrast Audit / AI Implementation Handoff</title><style>{css}</style></head><body>
<header><div class="eyebrow">LUCET · UI CONTRAST AUDIT · 2026-10-18</div><h1>Text &amp; surface contrast<br>AI implementation handoff</h1><p class="lead">Fix shared foreground / surface pairing and readable text hierarchy first. Preserve valid dark-on-light controls. Keep unverified black-on-dark reports separate from confirmed findings.</p><p class="muted">Native macOS app · macOS 27.0.1 · Chinese application UI inspected · Report only; application source unchanged</p><div class="stats"><div><b>6</b><span>Observed issue categories</span></div><div><b>2</b><span>P1 priority fixes</span></div><div><b>4</b><span>P2 follow-up fixes</span></div><div><b>2</b><span>Separate risk / scope items</span></div></div><nav><a href="#scope">Scope &amp; evidence</a><a href="#findings">Findings</a><a href="#risks">Theme &amp; capture risks</a><a href="#coverage">Coverage</a><a href="#handoff">Implementation guardrails</a><a href="audit.json">Machine-readable JSON</a><button class="print-button" onclick="window.print()">Print / save PDF</button></nav></header>
<main><section id="scope" class="section"><h2>Conclusion and evidence boundary</h2><p>{escape(report['main_conclusion'])} Most values and primary headings are clear; the weaker elements are parameter names, preset captions, explanatory text, and transport symbols on pale buttons.</p><div class="callout"><p><strong>User-reported black text on dark backgrounds:</strong> do not mark this exact failure as reproduced. The observed dark-panel issue is dim gray text. Explicit black foregrounds in the reviewed source are generally paired with bright surfaces. A separate capture-path comment documents near-black text in generated screenshots; investigate R02 without assuming it explains the live report.</p></div><p><strong>Theme constraint:</strong> <code>MediaWorkbenchApp.swift:22</code> forces <code>.preferredColorScheme(.dark)</code>. Switching the OS to Light did not produce a complete light app theme. Pale button surfaces and controls were still inspected. The original system appearance was Auto and was restored.</p><h3>Design targets, not certification</h3><p>Use 4.5:1 for normal text and 3:1 for necessary symbols as design targets. See <a href="https://www.w3.org/WAI/WCAG22/Understanding/contrast-minimum.html">W3C text contrast guidance</a> and <a href="https://www.w3.org/WAI/WCAG22/Understanding/non-text-contrast.html">non-text contrast guidance</a>. Disabled, decorative, and fully system-managed controls require applicability checks. This inspection does not establish complete accessibility compliance.</p><p>Contrast numbers are approximate raster estimates from current-run captures, converted to sRGB. Translucency, wallpaper tinting, antialiasing, and capture compression affect the samples. Resolve final foreground and background colors during implementation before making a compliance claim. Coordinates, representative colors, and methods are in <code>contrast-samples.json</code>.</p><h3>Version and reproduction constraint</h3><p>Source: <code>improve-workbench @ {report['source_commit']}</code>.<br>Runtime: <code>{escape(report['runtime_app'])}</code>.<br>{escape(report['version_limit'])}</p></section>
<section id="findings" class="section"><h2>Prioritized findings</h2><p>P1: fix core interaction legibility first. P2: improve readable hierarchy and state clarity.</p><div class="scroll"><table><thead><tr><th>ID</th><th>Priority</th><th>Finding</th></tr></thead><tbody>{issue_rows}</tbody></table></div></section>
{issue_sections}
<section id="risks" class="section"><h2>Separate theme and capture-path items</h2>{risk_sections}<h3>Preserve valid dark-on-light pairs</h3>{bullets(report['do_not_change_blindly'])}</section>
<section id="coverage" class="section"><h2>Inspection steps and coverage</h2><p>All accepted screenshots were captured and inspected in this audit run. Embedded detail images are unmodified crops. Original captures remain in <code>screenshots/</code>; some contain personal photos or capture metadata. This report and its evidence have only been saved locally.</p><div class="scroll"><table><thead><tr><th>Step</th><th>Surface</th><th>Health</th><th>Evidence / limitation</th></tr></thead><tbody>{coverage_rows}</tbody></table></div><h3>Not covered</h3>{bullets(report['not_covered'])}</section>
<section id="handoff" class="section"><h2>Instructions for the implementing AI</h2><p>The user requested an audit report and will handle fixes later. This artifact does not itself authorize source edits or publication.</p>{bullets(report['handoff_instructions'])}<h3>Suggested sequence</h3><ol>{''.join('<li>'+escape(x)+'</li>' for x in report['suggested_fix_order'])}</ol><h3>Completion evidence to provide after authorized fixes</h3><p>For each finding, report the code changes, the tested states, fresh live screenshots, resolved color measurements where available, and remaining exceptions. Keep source-only risks and loading-blocked surfaces separate from verified fixes.</p><div class="callout"><p><strong>Handoff files:</strong> <code>index.html</code> is the self-contained visual report. <a href="audit.json"><code>audit.json</code></a> contains structured findings, reproduction steps, source locations, acceptance criteria, evidence IDs, coverage gaps, and guardrails. <code>contrast-samples.json</code> preserves the original approximate measurements.</p></div></section></main><footer>Lucet · Local contrast audit · 2026-10-18<br>No application source edits, commits, pushes, or publication were performed. System appearance restored to Auto.</footer></body></html>'''
(ROOT/'index.html').write_text(html)
print('Generated English index.html and audit.json; 6 issue categories, 2 risks, 12 inspection steps.')
