import { Prop, Schema, SchemaFactory } from '@nestjs/mongoose';
import { HydratedDocument } from 'mongoose';

@Schema({ collection: 'categories', timestamps: true })
export class Category {
  @Prop({
    type: String,
    required: true,
    trim: true,
    minlength: 1,
    maxlength: 100,
  })
  name!: string;

  @Prop({ type: String, required: true, unique: true, select: false })
  normalizedName!: string;

  @Prop({ type: String, default: '', trim: true, maxlength: 2000 })
  description!: string;

  createdAt!: Date;
  updatedAt!: Date;
}

export type CategoryDocument = HydratedDocument<Category>;
export const CategorySchema = SchemaFactory.createForClass(Category);
