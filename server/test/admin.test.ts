import { describe, it, expect } from 'vitest';
import Fastify from 'fastify';

// Stub pool before importing the route module
vi.mock('../src/db.js', () => ({
	pool: {
		query: vi.fn(async () => ({ rows: [], rowCount: 0 })),
	},
}));

import { vi } from 'vitest';
import { adminRoutes } from '../src/routes/admin.js';

async function makeApp() {
	const app = Fastify();
	await app.register(adminRoutes, { prefix: '/admin' });
	return app;
}

describe('admin routes', () => {
	it('lists channels without auth (LAN is the boundary)', async () => {
		const app = await makeApp();
		const res = await app.inject({ method: 'GET', url: '/admin/api/channels' });
		expect(res.statusCode).toBe(200);
		expect(res.json()).toEqual([]);
	});

	it('enforces position range on profile create', async () => {
		const app = await makeApp();
		const res = await app.inject({
			method: 'POST',
			url: '/admin/api/profiles',
			headers: { 'content-type': 'application/json' },
			payload: { name: 'Kids', channel_ids: [], position: 5 },
		});
		expect(res.statusCode).toBe(400);
	});
});
