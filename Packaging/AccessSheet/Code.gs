// 08FOSE sign-up sheet script.
//
// Lives in the Apps Script project bound to the "Verification Code Form(응답)"
// spreadsheet, with one installable trigger: sendCode / From spreadsheet /
// On form submit. This copy is kept in the repo for reference; the live one
// is whatever is pasted in that project.
//
// Every form submission carries Email, Device ID and Code.
//   - A 6-character Code: mail it to Email (the app's sign-up).
//   - Code "WITHDRAW":    Delete Account from the app's Settings. Mask this
//                         device's rows, mark them 비활성, delete the raw
//                         form responses and this submission's own row.
function sendCode(e) {
  var v = e.namedValues;
  var email = String((v['Email'] || [''])[0]).trim();
  var device = String((v['Device ID'] || [''])[0]).trim();
  var code = String((v['Code'] || [''])[0]).trim().toUpperCase();

  if (code === 'WITHDRAW') { withdraw(e, email, device); return; }

  if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(email)) return;
  if (!/^[A-Z0-9]{6}$/.test(code)) return;

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

// Today's mail quota is used up: tell the app through the published tab.
function markQuotaFull() {
  var today = Utilities.formatDate(new Date(), 'Asia/Seoul', 'yyyy-MM-dd');
  SpreadsheetApp.getActive().getSheetByName('blocked')
    .getRange('B1').setValue('QUOTA_FULL ' + today);
}

function withdraw(e, email, device) {
  if (!email || !device) return;
  var sheet = e.range.getSheet();
  var ownRow = e.range.getRow();
  var head = sheet.getRange(1, 1, 1, sheet.getLastColumn()).getValues()[0];
  var cDevice = head.indexOf('Device ID');
  var cEmail = head.indexOf('Email');
  var cStatus = head.indexOf('Status');
  if (cDevice < 0 || cEmail < 0 || cStatus < 0) return;

  // Rows of this Mac with this address: keep them, masked and 비활성.
  var last = sheet.getLastRow();
  if (last >= 2) {
    var rows = sheet.getRange(2, 1, last - 1, head.length).getValues();
    for (var i = 0; i < rows.length; i++) {
      var r = i + 2;
      if (r === ownRow) continue;
      if (String(rows[i][cDevice]).trim() !== device) continue;
      if (String(rows[i][cEmail]).trim().toLowerCase() !== email.toLowerCase()) continue;
      sheet.getRange(r, cDevice + 1).setValue(maskDevice(device));
      sheet.getRange(r, cEmail + 1).setValue(maskEmail(email));
      sheet.getRange(r, cStatus + 1).setValue('비활성');
    }
  }

  // The form keeps its own copy of every response; remove this Mac's.
  var formUrl = SpreadsheetApp.getActive().getFormUrl();
  if (formUrl) {
    var form = FormApp.openByUrl(formUrl);
    form.getResponses().forEach(function (resp) {
      var answers = {};
      resp.getItemResponses().forEach(function (ir) {
        answers[ir.getItem().getTitle()] = String(ir.getResponse()).trim();
      });
      if (answers['Device ID'] === device &&
          String(answers['Email'] || '').toLowerCase() === email.toLowerCase()) {
        form.deleteResponse(resp.getId());
      }
    });
  }

  // Finally the WITHDRAW submission's own row, which holds the raw values.
  sheet.deleteRow(ownRow);
}

// 323CAB60E7ABBF3E -> *************F3E
function maskDevice(id) {
  var s = String(id);
  if (s.length <= 3) return s;
  return new Array(s.length - 3 + 1).join('*') + s.slice(-3);
}

// byeongsu.kim@influential.co.kr -> by**********@in***************
// me@panopt.net                  -> me@pa********
function maskEmail(email) {
  var at = email.indexOf('@');
  if (at < 0) return keep2(email);
  return keep2(email.slice(0, at)) + '@' + keep2(email.slice(at + 1));
}

function keep2(s) {
  if (s.length <= 2) return s;
  return s.slice(0, 2) + new Array(s.length - 2 + 1).join('*');
}
