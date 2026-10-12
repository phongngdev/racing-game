import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument, Types } from 'mongoose';
import { Category } from '../categories/category.schema.js';

@Schema({ collection: 'products', timestamps: true })
export class Product {
  @Prop({
    type: String,
    required: true,
    trim: true,
    minlength: 1,
    maxlength: 120,
  })
  name!: string;

  @Prop({ type: String, default: '', trim: true, maxlength: 2000 })
  description!: string;

  @Prop({ type: Number, required: true, min: 0 })
  price!: number;

  @Prop({ type: Types.ObjectId, ref: Category.name, default: null })
  categoryId!: Types.ObjectId | null;

  createdAt!: Date;
  updatedAt!: Date;
}

export type ProductDocument = HydratedDocument<Product>;
export const ProductSchema = SchemaFactory.createForClass(Product);
