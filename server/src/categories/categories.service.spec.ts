import { ConflictException, NotFoundException } from '@nestjs/common';
import type { Model } from 'mongoose';
import { Product } from '../products/product.schema.js';
import { CategoryInputDto } from './category.dto.js';
import { Category } from './category.schema.js';
import { CategoriesService } from './categories.service.js';

describe('CategoriesService', () => {
  const id = '66c1a10d6b9a5e9a6a1c0123';
  const categoryDoc = {
    _id: { toString: () => id },
    name: 'Batteries',
    description: '',
    createdAt: new Date('2026-10-10T00:00:00.000Z'),
    updatedAt: new Date('2026-10-10T00:00:00.000Z'),
    deleteOne: vi.fn().mockResolvedValue(undefined),
  };
  const categories = {
    find: vi.fn(),
    findById: vi.fn(),
    create: vi.fn(),
    findByIdAndUpdate: vi.fn(),
  };
  const products = { updateMany: vi.fn() };
  const service = new CategoriesService(
    categories as unknown as Model<Category>,
    products as unknown as Model<Product>,
  );

  beforeEach(() => vi.clearAllMocks());

  it('stores a normalized unique key while preserving the display name', async () => {
    categories.create.mockResolvedValue(categoryDoc);
    await expect(
      service.create({ name: ' Batteries ' } as CategoryInputDto),
    ).resolves.toMatchObject({ id, name: 'Batteries', description: '' });
    expect(categories.create).toHaveBeenCalledWith({
      name: 'Batteries',
      normalizedName: 'batteries',
      description: '',
    });
  });

  it('maps duplicate-name index errors to 409', async () => {
    categories.create.mockRejectedValue({ code: 11000 });
    await expect(
      service.create({ name: 'Batteries' } as CategoryInputDto),
    ).rejects.toBeInstanceOf(ConflictException);
  });

  it('unlinks related products before deleting the category', async () => {
    categories.findById.mockReturnValue({
      exec: vi.fn().mockResolvedValue(categoryDoc),
    });
    products.updateMany.mockReturnValue({
      exec: vi.fn().mockResolvedValue({}),
    });

    await service.delete(id);

    expect(products.updateMany).toHaveBeenCalledWith(
      { categoryId: categoryDoc._id },
      { $set: { categoryId: null } },
    );
    expect(products.updateMany.mock.invocationCallOrder[0]).toBeLessThan(
      categoryDoc.deleteOne.mock.invocationCallOrder[0],
    );
    expect(categoryDoc.deleteOne).toHaveBeenCalledOnce();
  });

  it('returns 404 instead of deleting products if the category is absent', async () => {
    categories.findById.mockReturnValue({
      exec: vi.fn().mockResolvedValue(null),
    });
    await expect(service.delete(id)).rejects.toBeInstanceOf(NotFoundException);
    expect(products.updateMany).not.toHaveBeenCalled();
  });
});
