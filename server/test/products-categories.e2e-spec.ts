import { INestApplication } from '@nestjs/common';
import { getModelToken } from '@nestjs/mongoose';
import { JwtService } from '@nestjs/jwt';
import { Test } from '@nestjs/testing';
import type { Model } from 'mongoose';
import request from 'supertest';
import { App } from 'supertest/types.js';
import { AppModule } from '../src/app.module.js';
import { setupHttp } from '../src/http-setup.js';
import { Category } from '../src/categories/category.schema.js';
import { Product } from '../src/products/product.schema.js';
import { User, UserRole } from '../src/users/user.schema.js';

describe('Products and categories (e2e)', () => {
  let app: INestApplication<App>;
  let users: Model<User>;
  let categories: Model<Category>;
  let products: Model<Product>;
  let adminToken: string;
  let userToken: string;

  beforeEach(async () => {
    const moduleFixture = await Test.createTestingModule({
      imports: [AppModule],
    }).compile();

    app = moduleFixture.createNestApplication();
    setupHttp(app);
    await app.init();

    users = app.get(getModelToken(User.name));
    categories = app.get(getModelToken(Category.name));
    products = app.get(getModelToken(Product.name));
    await Promise.all([users.init(), categories.init(), products.init()]);
    await Promise.all([
      products.deleteMany({}).exec(),
      categories.deleteMany({}).exec(),
      users.deleteMany({}).exec(),
    ]);

    const [admin, user] = await Promise.all([
      users.create({
        username: 'e2e_admin',
        email: 'e2e-admin@example.com',
        passwordHash: 'unused-in-this-suite',
        role: UserRole.Admin,
      }),
      users.create({
        username: 'e2e_user',
        email: 'e2e-user@example.com',
        passwordHash: 'unused-in-this-suite',
        role: UserRole.User,
      }),
    ]);

    const jwt = app.get(JwtService);
    [adminToken, userToken] = await Promise.all([
      jwt.signAsync({ sub: admin._id.toString() }),
      jwt.signAsync({ sub: user._id.toString() }),
    ]);
  });

  afterEach(async () => {
    await Promise.all([
      products.deleteMany({}).exec(),
      categories.deleteMany({}).exec(),
      users.deleteMany({}).exec(),
    ]);
    await app.close();
  });

  it('requires a valid JWT to list or view either resource', async () => {
    await request(app.getHttpServer()).get('/products').expect(401);
    await request(app.getHttpServer()).get('/categories').expect(401);
    await request(app.getHttpServer())
      .get('/products/66c1a10d6b9a5e9a6a1c0123')
      .expect(401);
    await request(app.getHttpServer())
      .get('/categories/66c1a10d6b9a5e9a6a1c0123')
      .expect(401);
    await request(app.getHttpServer())
      .get('/products')
      .set('Authorization', 'Bearer invalid-token')
      .expect(401);
  });

  it('allows User and Admin to list and view products and categories', async () => {
    const category = await createCategory('Batteries');
    const product = await createProduct({
      name: 'LiPo battery',
      price: 39.5,
      categoryId: category.id,
    });

    for (const token of [userToken, adminToken]) {
      await request(app.getHttpServer())
        .get('/products')
        .set('Authorization', `Bearer ${token}`)
        .expect(200)
        .expect(({ body }) => expect(body).toHaveLength(1));
      await request(app.getHttpServer())
        .get(`/products/${product.id}`)
        .set('Authorization', `Bearer ${token}`)
        .expect(200)
        .expect(({ body }) => expect(body.id).toBe(product.id));
      await request(app.getHttpServer())
        .get('/categories')
        .set('Authorization', `Bearer ${token}`)
        .expect(200)
        .expect(({ body }) => expect(body).toHaveLength(1));
      await request(app.getHttpServer())
        .get(`/categories/${category.id}`)
        .set('Authorization', `Bearer ${token}`)
        .expect(200)
        .expect(({ body }) => expect(body.id).toBe(category.id));
    }
  });

  it('allows Admin to create, list, view, replace, and delete products', async () => {
    const category = await createCategory('Electronics');
    const product = await createProduct({
      name: ' ESC ',
      price: 59.99,
      categoryId: category.id,
    });
    expect(product).toMatchObject({
      name: 'ESC',
      description: '',
      price: 59.99,
      categoryId: category.id,
    });
    expect(product).not.toHaveProperty('_id');
    expect(product).not.toHaveProperty('__v');

    await request(app.getHttpServer())
      .put(`/products/${product.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Replacement ESC', price: 70 })
      .expect(200)
      .expect(({ body }) => {
        expect(body).toMatchObject({
          id: product.id,
          name: 'Replacement ESC',
          description: '',
          price: 70,
          categoryId: null,
        });
      });

    await request(app.getHttpServer())
      .delete(`/products/${product.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(204);
    await request(app.getHttpServer())
      .get(`/products/${product.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(404);
  });

  it('allows Admin to create, list, view, replace, and delete categories', async () => {
    const category = await createCategory('Tires');
    expect(category).toMatchObject({
      name: 'Tires',
      description: '',
    });

    await request(app.getHttpServer())
      .put(`/categories/${category.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Wheels', description: 'Wheel and tire parts.' })
      .expect(200)
      .expect(({ body }) => {
        expect(body).toMatchObject({
          id: category.id,
          name: 'Wheels',
          description: 'Wheel and tire parts.',
        });
      });

    await request(app.getHttpServer())
      .delete(`/categories/${category.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(204);
    await request(app.getHttpServer())
      .get(`/categories/${category.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(404);
  });

  it('blocks User from every Admin-only write endpoint', async () => {
    const category = await createCategory('Drivetrain');
    const product = await createProduct({ name: 'Servo', price: 25 });
    const auth = `Bearer ${userToken}`;

    await request(app.getHttpServer())
      .post('/products')
      .set('Authorization', auth)
      .send({ name: 'Motor', price: 100 })
      .expect(403);
    await request(app.getHttpServer())
      .put(`/products/${product.id}`)
      .set('Authorization', auth)
      .send({ name: 'Motor', price: 100 })
      .expect(403);
    await request(app.getHttpServer())
      .delete(`/products/${product.id}`)
      .set('Authorization', auth)
      .expect(403);
    await request(app.getHttpServer())
      .post('/categories')
      .set('Authorization', auth)
      .send({ name: 'Motor parts' })
      .expect(403);
    await request(app.getHttpServer())
      .put(`/categories/${category.id}`)
      .set('Authorization', auth)
      .send({ name: 'Motor parts' })
      .expect(403);
    await request(app.getHttpServer())
      .delete(`/categories/${category.id}`)
      .set('Authorization', auth)
      .expect(403);
  });

  it('uses the current database role instead of trusting a JWT role claim', async () => {
    const userId = (await users.findOne({ username: 'e2e_user' }).exec())!._id;
    const forgedToken = await app
      .get(JwtService)
      .signAsync({ sub: userId.toString(), role: UserRole.Admin });

    await request(app.getHttpServer())
      .post('/categories')
      .set('Authorization', `Bearer ${forgedToken}`)
      .send({ name: 'Forbidden category' })
      .expect(403);
    await request(app.getHttpServer())
      .post('/categories')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Role ignored', role: UserRole.User })
      .expect(400);
  });

  it('rejects duplicate category names case-insensitively on create and replace', async () => {
    const category = await createCategory('Racing Parts');
    await request(app.getHttpServer())
      .post('/categories')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: ' racing parts ' })
      .expect(409);

    const other = await createCategory('Body');
    await request(app.getHttpServer())
      .put(`/categories/${other.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'RACING PARTS' })
      .expect(409);
    await request(app.getHttpServer())
      .get(`/categories/${category.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200);
  });

  it('rejects invalid bodies, invalid ids, and missing resources with clear statuses', async () => {
    await request(app.getHttpServer())
      .post('/products')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: ' ', price: -1 })
      .expect(400);
    await request(app.getHttpServer())
      .post('/products')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Motor', price: '20' })
      .expect(400);
    await request(app.getHttpServer())
      .post('/products')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Motor', price: 20, categoryId: 'invalid' })
      .expect(400);
    await request(app.getHttpServer())
      .post('/products')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Motor', price: 20, role: UserRole.Admin })
      .expect(400);
    await request(app.getHttpServer())
      .post('/categories')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: '   ' })
      .expect(400);
    await request(app.getHttpServer())
      .get('/products/not-an-object-id')
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(400);
    await request(app.getHttpServer())
      .put('/categories/66c1a10d6b9a5e9a6a1c0123')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Missing' })
      .expect(404);
  });

  it('requires a referenced category to exist', async () => {
    await request(app.getHttpServer())
      .post('/products')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({
        name: 'Orphaned product',
        price: 10,
        categoryId: '66c1a10d6b9a5e9a6a1c0123',
      })
      .expect(404);
  });

  it('deleting a category retains its products and sets only their categoryId to null', async () => {
    const deletedCategory = await createCategory('To unlink');
    const retainedCategory = await createCategory('Keep linked');
    const linked = await createProduct({
      name: 'Linked product',
      price: 12,
      description: 'Keep all these fields.',
      categoryId: deletedCategory.id,
    });
    const unrelated = await createProduct({
      name: 'Unrelated product',
      price: 13,
      categoryId: retainedCategory.id,
    });

    await request(app.getHttpServer())
      .delete(`/categories/${deletedCategory.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(204);

    await request(app.getHttpServer())
      .get(`/products/${linked.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200)
      .expect(({ body }) => {
        expect(body).toMatchObject({
          id: linked.id,
          name: 'Linked product',
          description: 'Keep all these fields.',
          price: 12,
          categoryId: null,
        });
      });
    await request(app.getHttpServer())
      .get(`/products/${unrelated.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200)
      .expect(({ body }) => expect(body.categoryId).toBe(retainedCategory.id));
  });

  it('documents product and category operations with Bearer security in Swagger', async () => {
    const { body } = await request(app.getHttpServer())
      .get('/api/docs-json')
      .expect(200);

    for (const path of [
      '/products',
      '/products/{id}',
      '/categories',
      '/categories/{id}',
    ]) {
      expect(body.paths[path]).toBeDefined();
      for (const operation of Object.values(body.paths[path]) as Array<
        Record<string, unknown>
      >) {
        expect(operation['security']).toEqual([{ bearer: [] }]);
      }
    }
    expect(body.paths['/products/{id}'].put).toBeDefined();
    expect(body.paths['/categories/{id}'].put).toBeDefined();
  });

  async function createCategory(name: string): Promise<{ id: string }> {
    const { body } = await request(app.getHttpServer())
      .post('/categories')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name })
      .expect(201);
    return body as { id: string };
  }

  async function createProduct(input: {
    name: string;
    price: number;
    description?: string;
    categoryId?: string | null;
  }): Promise<{ id: string } & Record<string, unknown>> {
    const { body } = await request(app.getHttpServer())
      .post('/products')
      .set('Authorization', `Bearer ${adminToken}`)
      .send(input)
      .expect(201);
    return body as { id: string } & Record<string, unknown>;
  }
});
