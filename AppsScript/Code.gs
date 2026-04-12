// ============================================================
// Telemax — Google Apps Script Backend
// ============================================================
// SETUP:
// 1. Create a new Google Sheets.
// 2. Extensions → Apps Script.
// 3. Paste all this code into Code.gs .
// 4. Deploy → New Version → Web Application:
// • Run as: Me
// • Who has access: Anyone
// 5. Copy the URL and paste it into Telemax during registration.
// ============================================================

const SS = SpreadsheetApp.getActiveSpreadsheet();

// ---------- sheet helpers ----------

function sheet(name, headers) {
  let s = SS.getSheetByName(name);
  if (!s) {
    s = SS.insertSheet(name);
    if (headers && headers.length) s.appendRow(headers);
  }
  return s;
}

function initSheets() {
  sheet('Users',    ['userId','username','displayName','publicKey','avatarFileId','createdAt','lastSeen']);
  sheet('Messages', ['messageId','chatId','senderId','encryptedKeys','encryptedContent','timestamp','type','fileId','isEdited','isDeleted','readBy']);
  sheet('Groups',   ['groupId','name','members','adminId','createdAt','avatarFileId']);
}

// ---------- routing ----------

function doGet(e)  { return handle(e.parameter); }
function doPost(e) { return handle(JSON.parse(e.postData.contents)); }

function handle(p) {
  try {
    initSheets();
    const r = route(p.action, p);
    return json({ success: true, data: r });
  } catch (err) {
    return json({ success: false, error: err.message });
  }
}

function route(action, p) {
  switch (action) {
    case 'register':        return registerUser(p);
    case 'getUser':         return getUser(p);
    case 'searchUsers':     return searchUsers(p);
    case 'sendMessage':     return sendMessage(p);
    case 'getMessages':     return getMessages(p);
    case 'getChats':        return getChats(p);
    case 'editMessage':     return editMessage(p);
    case 'deleteMessage':   return deleteMessage(p);
    case 'deleteChat':      return deleteChat(p);
    case 'createGroup':     return createGroup(p);
    case 'getGroups':       return getGroups(p);
    case 'updateGroup':     return updateGroup(p);
    case 'addGroupMember':  return addGroupMember(p);
    case 'removeGroupMember': return removeGroupMember(p);
    case 'setGroupAdmin':   return setGroupAdmin(p);
    case 'uploadFile':      return uploadFile(p);
    case 'getFile':         return getFile(p);
    case 'markRead':        return markRead(p);
    case 'updatePresence':  return updatePresence(p);
    default: throw new Error('Unknown action: ' + action);
  }
}

function json(obj) {
  return ContentService.createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);
}

// ==================== USERS ====================

function registerUser(p) {
  const s = SS.getSheetByName('Users');
  const d = s.getDataRange().getValues();

  for (let i = 1; i < d.length; i++) {
    if (d[i][0] === p.userId)  throw new Error('User already registered');
    if (d[i][1] === p.username) throw new Error('Username already taken');
  }

  const now = Date.now();
  s.appendRow([p.userId, p.username, p.displayName, p.publicKey, '', Number(p.createdAt), now]);

  return {
    id: p.userId, username: p.username, displayName: p.displayName,
    publicKey: p.publicKey, avatarFileId: null, createdAt: Number(p.createdAt),
    lastSeen: now
  };
}

function getUser(p) {
  const d = SS.getSheetByName('Users').getDataRange().getValues();
  for (let i = 1; i < d.length; i++) {
    if (d[i][0] === p.userId) {
      return { id: d[i][0], username: d[i][1], displayName: d[i][2],
               publicKey: d[i][3], avatarFileId: d[i][4] || null, createdAt: d[i][5],
               lastSeen: d[i][6] || d[i][5] };
    }
  }
  throw new Error('User not found');
}

function searchUsers(p) {
  const d = SS.getSheetByName('Users').getDataRange().getValues();
  const q = (p.query || '').toLowerCase();
  const out = [];
  for (let i = 1; i < d.length; i++) {
    if (d[i][1].toLowerCase().includes(q) || d[i][2].toLowerCase().includes(q)) {
      out.push({ id: d[i][0], username: d[i][1], displayName: d[i][2],
                 publicKey: d[i][3], avatarFileId: d[i][4] || null, createdAt: d[i][5],
                 lastSeen: d[i][6] || d[i][5] });
    }
  }
  return out;
}

// ==================== MESSAGES ====================

function sendMessage(p) {
  updatePresence({ userId: p.senderId });
  const ek = typeof p.encryptedKeys === 'string' ? p.encryptedKeys : JSON.stringify(p.encryptedKeys);
  SS.getSheetByName('Messages').appendRow([
    p.id, p.chatId, p.senderId, ek, p.encryptedContent,
    Number(p.timestamp), p.type, p.fileId || '', false, false, '[]'
  ]);
  return 'OK';
}

function getMessages(p) {
  if (p.userId) updatePresence({ userId: p.userId });
  const d = SS.getSheetByName('Messages').getDataRange().getValues();
  const since = Number(p.since) || 0;
  const out = [];
  for (let i = 1; i < d.length; i++) {
    if (d[i][1] === p.chatId && d[i][5] > since) {
      let ek; try { ek = JSON.parse(d[i][3]); } catch(_) { ek = {}; }
      let rb; try { rb = JSON.parse(d[i][10] || '[]'); } catch(_) { rb = []; }
      out.push({ id: d[i][0], chatId: d[i][1], senderId: d[i][2],
                 encryptedKeys: ek, encryptedContent: d[i][4],
                 timestamp: d[i][5], type: d[i][6], fileId: d[i][7] || null,
                 isEdited: d[i][8] === true, isDeleted: d[i][9] === true,
                 readBy: rb });
    }
  }
  return out;
}

function editMessage(p) {
  const s = SS.getSheetByName('Messages');
  const d = s.getDataRange().getValues();
  for (let i = 1; i < d.length; i++) {
    if (d[i][0] === p.messageId) {
      if (d[i][2] !== p.senderId) throw new Error('Not your message');
      const ek = typeof p.encryptedKeys === 'string' ? p.encryptedKeys : JSON.stringify(p.encryptedKeys);
      s.getRange(i + 1, 4).setValue(ek);
      s.getRange(i + 1, 5).setValue(p.encryptedContent);
      s.getRange(i + 1, 9).setValue(true);
      return 'OK';
    }
  }
  throw new Error('Message not found');
}

function deleteMessage(p) {
  const s = SS.getSheetByName('Messages');
  const d = s.getDataRange().getValues();
  for (let i = 1; i < d.length; i++) {
    if (d[i][0] === p.messageId) {
      if (p.forEveryone === true) {
        if (d[i][2] !== p.senderId) throw new Error('Not your message');
        s.getRange(i + 1, 5).setValue('');
        s.getRange(i + 1, 10).setValue(true);
      } else {
        // Remove user's key so they can't decrypt anymore
        let ek; try { ek = JSON.parse(d[i][3]); } catch(_) { ek = {}; }
        delete ek[p.senderId];
        s.getRange(i + 1, 4).setValue(JSON.stringify(ek));
      }
      return 'OK';
    }
  }
  throw new Error('Message not found');
}

function deleteChat(p) {
  const s = SS.getSheetByName('Messages');
  const d = s.getDataRange().getValues();
  const rows = [];
  for (let i = d.length - 1; i >= 1; i--) {
    if (d[i][1] === p.chatId) rows.push(i + 1);
  }
  for (const r of rows) s.deleteRow(r);
  return 'OK';
}

function getChats(p) {
  const d = SS.getSheetByName('Messages').getDataRange().getValues();
  const uid = p.userId;
  const map = {};

  for (let i = 1; i < d.length; i++) {
    let ek; try { ek = JSON.parse(d[i][3]); } catch(_) { ek = {}; }
    if (!ek[uid]) continue;

    const cid = d[i][1];
    if (!map[cid] || d[i][5] > map[cid].lastMessageTime) {
      map[cid] = {
        id: cid,
        isGroup: cid.length < 60,
        participants: Object.keys(ek),
        groupName: null,
        lastMessage: null,
        lastMessageTime: d[i][5]
      };
    }
  }

  // enrich group names
  const gs = SS.getSheetByName('Groups');
  if (gs) {
    const gd = gs.getDataRange().getValues();
    for (const cid in map) {
      if (map[cid].isGroup) {
        for (let i = 1; i < gd.length; i++) {
          if (gd[i][0] === cid) { map[cid].groupName = gd[i][1]; break; }
        }
      }
    }
  }

  return Object.values(map).sort((a, b) => b.lastMessageTime - a.lastMessageTime);
}

// ==================== GROUPS ====================

function createGroup(p) {
  const m = typeof p.members === 'string' ? p.members : JSON.stringify(p.members);
  SS.getSheetByName('Groups').appendRow([p.id, p.name, m, p.adminId, Number(p.createdAt), p.avatarFileId || '']);
  return { id: p.id, name: p.name, members: JSON.parse(m), adminId: p.adminId,
           createdAt: Number(p.createdAt), avatarFileId: p.avatarFileId || null };
}

function getGroups(p) {
  const d = SS.getSheetByName('Groups').getDataRange().getValues();
  const out = [];
  for (let i = 1; i < d.length; i++) {
    let m; try { m = JSON.parse(d[i][2]); } catch(_) { m = []; }
    if (m.includes(p.userId)) {
      out.push({ id: d[i][0], name: d[i][1], members: m, adminId: d[i][3],
                 createdAt: d[i][4], avatarFileId: d[i][5] || null });
    }
  }
  return out;
}

function updateGroup(p) {
  const s = SS.getSheetByName('Groups');
  const d = s.getDataRange().getValues();
  for (let i = 1; i < d.length; i++) {
    if (d[i][0] === p.groupId) {
      if (d[i][3] !== p.requesterId) throw new Error('Only admin can update group');
      if (p.name) s.getRange(i + 1, 2).setValue(p.name);
      return 'OK';
    }
  }
  throw new Error('Group not found');
}

function addGroupMember(p) {
  const s = SS.getSheetByName('Groups');
  const d = s.getDataRange().getValues();
  for (let i = 1; i < d.length; i++) {
    if (d[i][0] === p.groupId) {
      let m; try { m = JSON.parse(d[i][2]); } catch(_) { m = []; }
      if (!m.includes(p.userId)) {
        m.push(p.userId);
        s.getRange(i + 1, 3).setValue(JSON.stringify(m));
      }
      return 'OK';
    }
  }
  throw new Error('Group not found');
}

function removeGroupMember(p) {
  const s = SS.getSheetByName('Groups');
  const d = s.getDataRange().getValues();
  for (let i = 1; i < d.length; i++) {
    if (d[i][0] === p.groupId) {
      if (d[i][3] !== p.requesterId && p.userId !== p.requesterId) throw new Error('Only admin can remove members');
      let m; try { m = JSON.parse(d[i][2]); } catch(_) { m = []; }
      m = m.filter(id => id !== p.userId);
      s.getRange(i + 1, 3).setValue(JSON.stringify(m));
      return 'OK';
    }
  }
  throw new Error('Group not found');
}

function setGroupAdmin(p) {
  const s = SS.getSheetByName('Groups');
  const d = s.getDataRange().getValues();
  for (let i = 1; i < d.length; i++) {
    if (d[i][0] === p.groupId) {
      if (d[i][3] !== p.requesterId) throw new Error('Only admin can transfer admin');
      s.getRange(i + 1, 4).setValue(p.newAdminId);
      return 'OK';
    }
  }
  throw new Error('Group not found');
}

// ==================== FILES (Google Drive) ====================

function getOrCreateFolder(name) {
  const props = PropertiesService.getScriptProperties();
  const cachedId = props.getProperty('folderId_' + name);

  // Try cached folder ID first
  if (cachedId) {
    try {
      const folder = DriveApp.getFolderById(cachedId);
      if (!folder.isTrashed()) return folder;
    } catch(_) { /* folder was deleted, recreate */ }
  }

  // Search existing folders
  const folders = DriveApp.getRootFolder().getFoldersByName(name);
  if (folders.hasNext()) {
    const folder = folders.next();
    props.setProperty('folderId_' + name, folder.getId());
    return folder;
  }

  // Create new folder
  const folder = DriveApp.createFolder(name);
  folder.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  props.setProperty('folderId_' + name, folder.getId());
  return folder;
}

function uploadFile(p) {
  const folder = getOrCreateFolder('Telemax');
  const blob = Utilities.newBlob(Utilities.base64Decode(p.fileData), p.mimeType, p.fileName);
  const file = folder.createFile(blob);
  file.setSharing(DriveApp.Access.ANYONE_WITH_LINK, DriveApp.Permission.VIEW);
  return file.getId();
}

function getFile(p) {
  const file = DriveApp.getFileById(p.fileId);
  const blob = file.getBlob();
  return {
    data: Utilities.base64Encode(blob.getBytes()),
    mimeType: blob.getContentType(),
    name: file.getName()
  };
}

// ==================== READ RECEIPTS ====================

function markRead(p) {
  updatePresence({ userId: p.userId });
  const s = SS.getSheetByName('Messages');
  const d = s.getDataRange().getValues();
  const ids = typeof p.messageIds === 'string' ? JSON.parse(p.messageIds) : (p.messageIds || []);
  const userId = p.userId;

  for (let i = 1; i < d.length; i++) {
    if (ids.includes(d[i][0])) {
      let rb; try { rb = JSON.parse(d[i][10] || '[]'); } catch(_) { rb = []; }
      if (!rb.includes(userId)) {
        rb.push(userId);
        s.getRange(i + 1, 11).setValue(JSON.stringify(rb));
      }
    }
  }
  return 'OK';
}

// ==================== PRESENCE ====================

function updatePresence(p) {
  const s = SS.getSheetByName('Users');
  const d = s.getDataRange().getValues();
  const now = Date.now();
  
  for (let i = 1; i < d.length; i++) {
    if (d[i][0] === p.userId) {
      s.getRange(i + 1, 7).setValue(now);
      return 'OK';
    }
  }rror('User not found')
  return 'OK';
}
