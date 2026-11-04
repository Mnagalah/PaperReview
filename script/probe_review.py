"""Small local-model prompt checks on a synthetic essay; not real student acceptance."""
import json,urllib.request,pathlib,time
lines=['A Day at the Park','Last Sunday, I goed to the park with my freind.','The weather were sunny and warm. We plays football','for two hour. My sister don\'t like sports, so she','read a book under a tree.','After lunch, we see a beautifull bird near the lake.','I was very exciting. We taked many photos and',"returned home at five o'clock. It was a happy day."]
cases=[
 ('plain_sentence', 'You are an English teacher. Correct grammar and spelling with the smallest edits. Return only the corrected sentence.', lines[1]),
 ('simple_chinese', '你是英语老师。检查语法和拼写，逐项列出原词、建议替换和简短中文原因。不要润色。', '\n'.join(lines)),
 ('anchored_json', '你是英语教师。只找明确的语法和拼写错误。输出JSON：{"issues":[{"line":2,"quote":"原文词组","occurrence":1,"kind":"grammar或spelling","suggestion":"最小修改后的词组","explanation":"中文原因"}]}。quote必须逐字引用该行原文。suggestion只能是英文词或短语，不含行号。例：原句She go home. 中go建议goes，原因第三人称单数。', '\n'.join(f'[L{i+1}] {t}' for i,t in enumerate(lines)))
]
results=[]
for name,system,user in cases:
 body=dict(model='MiniCPM5-2B',messages=[dict(role='system',content=system),dict(role='user',content=user)],stream=False,temperature=.2,top_p=.95,min_p=0,max_tokens=2048)
 request=urllib.request.Request('http://127.0.0.1:18501/v1/chat/completions',data=json.dumps(body).encode(),headers={'Content-Type':'application/json'})
 start=time.monotonic()
 with urllib.request.urlopen(request,timeout=180) as response: result=json.load(response)
 results.append(dict(name=name,seconds=time.monotonic()-start,request=body,response=result))
 print(name, result['choices'][0]['message'], flush=True)
pathlib.Path('docs/verification/review-prompt-probes.json').write_text(json.dumps(results,ensure_ascii=False,indent=2))
