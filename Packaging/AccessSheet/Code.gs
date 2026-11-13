// 08FOSE sign-up sheet script.
//
// Lives in the Apps Script project bound to the "Verification Code Form(응답)"
// spreadsheet, with two installable triggers: sendCode / From spreadsheet /
// On form submit, and onMembersChange / From spreadsheet /
// On change. onEdit below is a simple trigger and needs no setup.
// This copy is kept in the repo for reference; the live one is whatever is
// pasted in that project.
//
// Tabs
//   설문지 응답 시트1  Raw form log. Every submission lands here. Not edited.
//   Members           One row per email: the list to manage. Created by this
//                     script. Change Status (dropdown) or Memo by hand.
//   blocked           Published as CSV for the app. Rewritten by this script
//                     from Members: email hash, status, device IDs. No email.
//
// Status
//   Pending    Code sent, not verified yet.
//   Active     Verified and in use.
//   Rejoined   Same as Active, but the email had withdrawn before.
//   Inactive   Blocked by you. No new codes; the app stops on its next check.
//   Withdrawn  Left from the app's Settings. Email and devices are masked.
//
// Each submission carries Email, Device ID and Code:
//   6 characters  Send that code to Email.
//   VERIFIED      The code was entered correctly on Device ID.
//   WITHDRAW      Delete Account from the app's Settings.

var MEMBERS = 'Members';
var PUBLIC = 'blocked';
// Must match AccessConfig.directoryMarker in the app.
var DIRECTORY_MARKER = '08FOSE_DIRECTORY';
var HEAD = ['Email', 'Status', 'Devices', 'Code', 'Joined', 'Verified', 'Left', 'Memo', 'Email Hash'];
var C = { email: 0, status: 1, devices: 2, code: 3, joined: 4, verified: 5, left: 6, memo: 7, hash: 8 };
var STATUSES = ['Pending', 'Active', 'Rejoined', 'Inactive', 'Withdrawn'];
var MAX_DEVICES = 5;

function sendCode(e) {
  var v = e.namedValues;
  var email = String((v['Email'] || [''])[0]).trim();
  var device = String((v['Device ID'] || [''])[0]).trim();
  var code = String((v['Code'] || [''])[0]).trim().toUpperCase();
  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email) || !device) return;

  var lock = LockService.getScriptLock();
  lock.waitLock(20000);
  try {
    if (code === 'VERIFIED') verified(email, device);
    else if (code === 'WITHDRAW') withdraw(e, email, device);
    else if (/^[A-Z0-9]{6}$/.test(code)) requestCode(email, device, code);
    publish();
  } finally {
    lock.releaseLock();
  }
}

// Simple trigger: a Status or Devices edit by hand reaches the app.
function onEdit(e) {
  if (e && e.range && e.range.getSheet().getName() === MEMBERS) publish();
}

// Installable trigger (From spreadsheet / On change): deleting or inserting
// rows doesn't fire onEdit, so a deleted member would linger in the
// published list until the next form submission.
function onMembersChange(e) {
  if (e && (e.changeType === 'REMOVE_ROW' || e.changeType === 'INSERT_ROW' ||
            e.changeType === 'OTHER')) publish();
}

// MARK: - Events

function requestCode(email, device, code) {
  var m = members();
  var row = findRow(m, email);
  if (row) {
    var status = m.getRange(row, C.status + 1).getValue();
    if (status === 'Inactive') return;
    if (status === 'Withdrawn') {
      // Coming back: unmask the row, drop the old (masked) devices and start
      // again from Pending. Left stays filled, so verifying marks it Rejoined.
      m.getRange(row, C.email + 1).setValue(email);
      m.getRange(row, C.devices + 1).setValue('');
      m.getRange(row, C.status + 1).setValue('Pending');
    }
    var devices = splitDevices(m.getRange(row, C.devices + 1).getValue());
    if (devices.indexOf(device) < 0 && devices.length >= MAX_DEVICES) return;
    m.getRange(row, C.code + 1).setValue(code);
    rememberRequest(email, device);
  } else {
    var values = ['', '', '', '', '', '', '', '', ''];
    values[C.email] = email;
    values[C.status] = 'Pending';
    values[C.code] = code;
    values[C.hash] = hashEmail(email);
    m.appendRow(values);
    rememberRequest(email, device);
  }

  // Same address: at most 5 mails an hour.
  var cache = CacheService.getScriptCache();
  var key = 'n:' + email.toLowerCase();
  var count = Number(cache.get(key) || 0);
  if (count >= 5) return;
  cache.put(key, String(count + 1), 3600);

  if (MailApp.getRemainingDailyQuota() < 1) { markQuotaFull(); return; }
  MailApp.sendEmail({
    to: email,
    name: '08FOSE',
    subject: '08FOSE verification code',
    body: 'Your 08FOSE verification code is ' + code + '\n\n' +
          'Enter it in the app to continue.'
  });
  if (MailApp.getRemainingDailyQuota() < 1) markQuotaFull();
}

function verified(email, device) {
  // Only a Mac that asked for a code in the last 6 hours can be added, so a
  // forged VERIFIED can't fill someone else's five slots.
  if (!requestedBy(email, device)) return;
  var m = members();
  var row = findRow(m, email);
  if (!row) return;
  var status = m.getRange(row, C.status + 1).getValue();
  if (status === 'Inactive') return;

  var devices = splitDevices(m.getRange(row, C.devices + 1).getValue());
  if (devices.indexOf(device) < 0) {
    if (devices.length >= MAX_DEVICES) return;
    devices.push(device);
  }
  // A Mac belongs to one account: take it off any other row.
  var last = m.getLastRow();
  if (last >= 2) {
    var cells = m.getRange(2, C.devices + 1, last - 1, 1).getValues();
    for (var i = 0; i < cells.length; i++) {
      var r = i + 2;
      if (r === row) continue;
      var list = splitDevices(cells[i][0]);
      var at = list.indexOf(device);
      if (at >= 0) { list.splice(at, 1); m.getRange(r, C.devices + 1).setValue(list.join(', ')); }
    }
  }

  var now = new Date();
  var hadLeft = m.getRange(row, C.left + 1).getValue() !== '';
  m.getRange(row, C.devices + 1).setValue(devices.join(', '));
  m.getRange(row, C.status + 1).setValue(hadLeft ? 'Rejoined' : 'Active');
  m.getRange(row, C.code + 1).setValue('');
  m.getRange(row, C.verified + 1).setValue(now);
  if (m.getRange(row, C.joined + 1).getValue() === '') m.getRange(row, C.joined + 1).setValue(now);
}

function withdraw(e, email, device) {
  var m = members();
  var row = findRow(m, email);
  // Only one of the account's own Macs can withdraw it.
  if (!row || splitDevices(m.getRange(row, C.devices + 1).getValue()).indexOf(device) < 0) {
    e.range.getSheet().deleteRow(e.range.getRow());
    return;
  }
  if (row) {
    var devices = splitDevices(m.getRange(row, C.devices + 1).getValue());
    m.getRange(row, C.email + 1).setValue(maskEmail(email));
    m.getRange(row, C.devices + 1).setValue(devices.map(maskDevice).join(', '));
    m.getRange(row, C.status + 1).setValue('Withdrawn');
    m.getRange(row, C.code + 1).setValue('');
    m.getRange(row, C.left + 1).setValue(new Date());
  }

  // Raw copies of this address: the form's own responses and the log rows.
  var formUrl = SpreadsheetApp.getActive().getFormUrl();
  if (formUrl) {
    var form = FormApp.openByUrl(formUrl);
    form.getResponses().forEach(function (resp) {
      var hit = resp.getItemResponses().some(function (ir) {
        return ir.getItem().getTitle() === 'Email' &&
               String(ir.getResponse()).trim().toLowerCase() === email.toLowerCase();
      });
      if (hit) form.deleteResponse(resp.getId());
    });
  }
  var log = e.range.getSheet();
  var head = log.getRange(1, 1, 1, log.getLastColumn()).getValues()[0];
  var cEmail = head.indexOf('Email');
  if (cEmail >= 0) {
    for (var r = log.getLastRow(); r >= 2; r--) {
      if (String(log.getRange(r, cEmail + 1).getValue()).trim().toLowerCase() === email.toLowerCase()) {
        log.deleteRow(r);
      }
    }
  }
}

// MARK: - Published list

// First line: the marker the app looks for, so it can tell the list from an
// empty or broken response. Then one line per account: email hash, status,
// device IDs separated by spaces. Plus QUOTA_FULL when today's mail quota is
// used up.
function publish() {
  var m = members();
  var out = [[DIRECTORY_MARKER, '1', '']];
  var last = m.getLastRow();
  if (last >= 2) {
    m.getRange(2, 1, last - 1, HEAD.length).getValues().forEach(function (r) {
      var hash = String(r[C.hash]).trim();
      if (!hash) return;
      out.push([hash, String(r[C.status]).trim(), splitDevices(r[C.devices]).join(' ')]);
    });
  }
  var props = PropertiesService.getScriptProperties();
  var quota = props.getProperty('quotaFull');
  var today = Utilities.formatDate(new Date(), 'Asia/Seoul', 'yyyy-MM-dd');
  if (quota === today) out.push(['QUOTA_FULL', quota, '']);
  else if (quota) props.deleteProperty('quotaFull');

  var sheet = SpreadsheetApp.getActive().getSheetByName(PUBLIC);
  // Write over the old rows first and only then drop what is left below, so
  // the tab is never empty in between.
  sheet.getRange(1, 1, out.length, 3).setValues(out);
  var extra = sheet.getLastRow() - out.length;
  if (extra > 0) sheet.getRange(out.length + 1, 1, extra, sheet.getMaxColumns()).clearContent();
}

function markQuotaFull() {
  var today = Utilities.formatDate(new Date(), 'Asia/Seoul', 'yyyy-MM-dd');
  PropertiesService.getScriptProperties().setProperty('quotaFull', today);
}

// MARK: - Helpers

function rememberRequest(email, device) {
  CacheService.getScriptCache().put('req:' + hashEmail(email) + ':' + device, '1', 21600);
}

function requestedBy(email, device) {
  return CacheService.getScriptCache().get('req:' + hashEmail(email) + ':' + device) === '1';
}

function members() {
  var ss = SpreadsheetApp.getActive();
  var m = ss.getSheetByName(MEMBERS);
  if (m) return m;
  m = ss.insertSheet(MEMBERS, 0);
  m.getRange(1, 1, 1, HEAD.length).setValues([HEAD]).setFontWeight('bold');
  m.setFrozenRows(1);
  var rule = SpreadsheetApp.newDataValidation().requireValueInList(STATUSES, true).build();
  m.getRange(2, C.status + 1, m.getMaxRows() - 1, 1).setDataValidation(rule);
  m.hideColumns(C.hash + 1);
  return m;
}

function findRow(m, email) {
  var last = m.getLastRow();
  if (last < 2) return 0;
  var hash = hashEmail(email);
  var hashes = m.getRange(2, C.hash + 1, last - 1, 1).getValues();
  for (var i = 0; i < hashes.length; i++) {
    if (String(hashes[i][0]) === hash) return i + 2;
  }
  return 0;
}

function splitDevices(cell) {
  return String(cell || '').split(/[\s,]+/).filter(function (s) { return s; });
}

// Must match AccessController.hashEmail in the app.
function hashEmail(email) {
  var bytes = Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256,
                                      '08FOSE:' + email.trim().toLowerCase(),
                                      Utilities.Charset.UTF_8);
  var hex = '';
  for (var i = 0; i < 8; i++) {
    var b = (bytes[i] + 256) % 256;
    hex += (b < 16 ? '0' : '') + b.toString(16);
  }
  return hex.toUpperCase();
}

// 323CAB60E7ABBF3E -> *************F3E
function maskDevice(id) {
  var s = String(id);
  if (s.length <= 3) return s;
  return new Array(s.length - 3 + 1).join('*') + s.slice(-3);
}

// byeongsu.kim@influential.co.kr -> by**********@in***************
function maskEmail(email) {
  var at = email.indexOf('@');
  if (at < 0) return keep2(email);
  return keep2(email.slice(0, at)) + '@' + keep2(email.slice(at + 1));
}

function keep2(s) {
  if (s.length <= 2) return s;
  return s.slice(0, 2) + new Array(s.length - 2 + 1).join('*');
}
