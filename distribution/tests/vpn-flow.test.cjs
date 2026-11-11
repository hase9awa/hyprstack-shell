const assert = require('node:assert/strict');
const {test} = require('node:test');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');
const flow = vm.createContext({});
vm.runInContext(fs.readFileSync(path.join(__dirname, '../../shell/utils/scripts/vpn-flow.js'), 'utf8')
    .replace(/^\.pragma library\s*/, ''), flow);
const ready = {hasProfile:true, profileCount:2, installed:true, mode:'tun', canTun:true};

test('the first connection progresses through explicit setup actions', () => {
    assert.equal(flow.primaryAction({profileCount:0}), 'import');
    assert.equal(flow.primaryAction({profileCount:2}), 'select');
    assert.equal(flow.primaryAction({...ready, installed:false, canTun:false}), 'install');
    assert.equal(flow.primaryAction({...ready, canTun:false}), 'authorize');
    assert.equal(flow.primaryAction(ready), 'connect');
});

test('proxy connections do not request tunnel privileges', () => {
    assert.equal(flow.primaryAction({...ready, mode:'proxy', canTun:false}), 'connect');
});

test('an existing connection can always be disconnected, including after permissions expire', () => {
    assert.equal(flow.primaryAction({...ready, connected:true, installed:false, canTun:false}), 'disconnect');
});

test('another provider is explicitly disconnected before starting a managed tunnel', () => {
    assert.equal(flow.primaryAction({...ready, otherConnected:true}), 'disconnect-other');
    assert.equal(flow.primaryAction({otherConnected:true, profileCount:0}), 'disconnect-other');
});

test('busy operations cannot start a second action', () => {
    for (const state of [{}, ready, {connected:true}, {otherConnected:true}])
        assert.equal(flow.primaryAction({...state, busy:true}), 'busy');
});

function serviceFunction(name, context) {
    const source = fs.readFileSync(path.join(__dirname, '../../shell/services/VPN.qml'), 'utf8');
    const match = source.match(new RegExp('function ' + name + '\\(([^)]*)\\)(?:\\s*:\\s*\\w+)?\\s*\\{([\\s\\S]*?)\\n    \\}'));
    assert.ok(match, name);
    return vm.runInNewContext('(function(' + match[1].replace(/:\s*\w+/g, '') + '){' + match[2] + '})', context);
}

test('startup waits for managed profile data before deciding whether to reconnect', () => {
    let connected = 0;
    const root = {status:{state:'disconnected'}, autoConnectPending:true, connect:()=>connected++};
    const managed = {loaded:false};
    const context = {root, active:{name:'native'}, ManagedVPN:managed, emitStatusToast:()=>{}};
    Object.defineProperty(context, 'status', {get:()=>root.status});
    const update = serviceFunction('updateStatus', context);
    update({state:'disconnected', connected:false});
    assert.equal(root.autoConnectPending, true);
    assert.equal(connected, 0);
    managed.loaded = true;
    update({state:'disconnected', connected:false});
    assert.equal(root.autoConnectPending, false);
    assert.equal(connected, 1);
});

test('selecting the managed provider never replaces another live connection', () => {
    let selected = '';
    const providers = [{id:'external-id', name:'external'}, {id:'native-id', name:'native'}];
    const context = {connected:true, active:{name:'external'}, providers,
        addProvider:()=>assert.fail('No provider needs to be added'), applySelectedProvider:id=>selected=id};
    const select = serviceFunction('selectManagedProvider', context);
    assert.equal(select(), false);
    assert.equal(selected, '');
    context.connected = false;
    assert.equal(select(), true);
    assert.equal(selected, 'native-id');
});

test('an incomplete managed setup opens its controls instead of running a failing connect command', () => {
    let opened = 0, started = 0;
    const managed = {needsSetup:true, openSettings:()=>opened++, run:command=>{assert.equal(command,'connect');started++;}};
    const connect = serviceFunction('connect', {active:{name:'native'}, ManagedVPN:managed});
    connect();
    assert.equal(opened, 1);
    assert.equal(started, 0);
    managed.needsSetup = false;
    connect();
    assert.equal(started, 1);
});
