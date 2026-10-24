import json, urllib.request, urllib.parse, sys

class VM:
    def __init__(self, base):
        self.base=base.rstrip('/')+'/'
        self.http=urllib.request.build_opener(urllib.request.ProxyHandler({}))
        self.isolate=self.call('getVM')['isolates'][0]['id']
    def call(self, method, **params):
        url=self.base+method+'?'+urllib.parse.urlencode({k:json.dumps(v) if isinstance(v,(dict,list,bool)) else v for k,v in params.items()})
        result=json.load(self.http.open(url,timeout=30))
        if 'error' in result:raise RuntimeError(result['error'])
        return result['result']
    def library(self, suffix):
        return next(l['id'] for l in self.call('getIsolate',isolateId=self.isolate)['libraries'] if l['uri'].endswith(suffix))
    def evaluate(self, target, expression):
        return self.call('evaluate',isolateId=self.isolate,targetId=target,expression=expression)
    def state(self, name):
        c=next(c for c in self.call('getClassList',isolateId=self.isolate)['classes'] if c['name']==name)
        return self.call('getInstances',isolateId=self.isolate,objectId=c['id'],limit=20)['instances']
    def field(self, ref, name):
        obj=self.call('getObject',isolateId=self.isolate,objectId=ref['id'])
        return next(f['value'] for f in obj['fields'] if f['decl']['name']==name)
    def decode(self, ref):
        kind=ref.get('kind')
        if kind=='Null':return None
        if kind=='Int':return int(ref['valueAsString'])
        if kind=='Double':return float(ref['valueAsString'])
        if kind=='Bool':return ref['valueAsString']=='true'
        if kind=='String' and not ref.get('valueAsStringIsTruncated'):return ref['valueAsString']
        obj=self.call('getObject',isolateId=self.isolate,objectId=ref['id'],offset=0,count=100000)
        if kind=='String':return obj['valueAsString']
        if kind in ('List','Set'):return [self.decode(x) for x in obj['elements']]
        if kind=='Map':return {self.decode(x['key']):self.decode(x['value']) for x in obj['associations']}
        raise ValueError((kind,ref.get('class',{}).get('name')))

if __name__=='__main__':
    vm=VM(sys.argv[1]);mode=sys.argv[2]
    if mode=='state':print(json.dumps(vm.state(sys.argv[3]),ensure_ascii=False))
    elif mode=='eval':print(json.dumps(vm.evaluate(sys.argv[3],sys.argv[4]),ensure_ascii=False))
