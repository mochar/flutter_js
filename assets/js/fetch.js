var window = global = globalThis;

function utf8Encode(bytes) {
	if (!bytes) return null
	let encodedString = '';
	for (let i = 0; i < bytes.length; i++) {
		encodedString += String.fromCharCode(bytes[i] & 0xFF);
	}
	return encodedString;
}

function uft8Decode(str) {
	let bytes = []
	for (let i = 0; i < str.length; i++) {
		const charCode = str.charCodeAt(i);
		bytes.push(charCode & 0xFF);
	}
	return bytes;
}

function fetch(url, options) {
	options = options || {};

	return new Promise((resolve, reject) => {
		const request = new XMLHttpRequest();
		const keys = [];
		const all = [];
		const headers = {};

		const response = () => ({
			ok: (request.status / 100 | 0) == 2,		// 200-299
			statusText: request.statusText,
			status: request.status,
			url: request.responseURL,
			text: () => request.responseText,
			json: () => {
				try {
					// console.log('RESPONSE TEXT IN FETCH: ' + request.responseText);
					return Promise.resolve(JSON.parse(request.responseText));
				} catch (e) {
					// console.log('ERROR on fetch parsing JSON: ' + e.message);
					return Promise.resolve(request.responseText);
				}
			},
			blob: () => Promise.resolve(new Blob([request.response])),
			arrayBuffer: () => uft8Decode(request.responseText),
			clone: response,
			headers: {
				keys: () => keys,
				entries: () => all,
				get: n => headers[n.toLowerCase()],
				has: n => n.toLowerCase() in headers
			},
			type: "default",
			bodyUsed: false
		});

		request.open(options.method || 'get', url, true);

		request.onload = () => {
			request.getAllResponseHeaders().replace(/^(.*?):[^\\S\\n]*([\\s\\S]*?)\$/gm, (m, key, value) => {
				keys.push(key = key.toLowerCase());
				all.push([key, value]);
				headers[key] = headers[key] ? `\${headers[key]},\${value}` : value;
			});
		};

		request.onerror = reject
		request.withCredentials = options.credentials == 'include';

		if (options.headers) {
			if (options.headers.constructor.name == 'Object') {
				for (const i in options.headers) {
					request.setRequestHeader(i, options.headers[i]);
				}
			} else { // if it is some Headers pollyfill, the way to iterate is through for of
				for (const header of options.headers) {
					request.setRequestHeader(header[0], header[1]);
				}
			}
		}

		request.onreadystatechange = function () {
			if (request.readyState == 4) {
				if (request.status == 200) {
					var rep = response()
					try {
						resolve(rep)
					} catch (e) {
						console.error("resolve error", e)
					}
				}
			}
		};
		var body = utf8Encode(options.body)
		request.send(body || null);
	});
}