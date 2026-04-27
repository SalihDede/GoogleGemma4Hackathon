[ TR ]
Görme engelli insanlar için farklı bir deneyim sunan bir uygulama geliştirmek istiyoruz. Bu uygulama, görme engelli kullanıcıların çevrelerindeki nesneleri tanımalarına yardımcı olacak ve onlara daha bağımsız bir yaşam sunacak. Uygulamanın temel amacı, görme engelli bireylerin günlük yaşamlarında karşılaştıkları zorlukları azaltmak ve onlara daha fazla özgürlük sağlamaktır. Bu yüzden standart llm çıktılarını görme engelli insanlar için görsel imgelerden izole edilerek daha zengin halde finetune edilemk için farklı sosyal alanlardan görseller toplanmıştır.

[ EN ]
We want to develop an application that provides a unique experience for visually impaired individuals. This application will help visually impaired users recognize objects in their surroundings and offer them a more independent life. The main objective of the application is to mitigate the challenges visually impaired people face in their daily lives and grant them greater freedom. For this reason, images from various social environments have been collected to fine-tune standard LLM outputs into a richer format, isolated from visual imagery specifically for visually impaired users.

Main source of data for finetuning the model is as follows:
MIT Indoor Scenes - 67 Indoor categories, and a total of 15620 images
https://www.kaggle.com/datasets/itsahmad/indoor-scenes-cvpr-2019


Labeled dataset ready for finetuning - huggingface repo : SalihHub/blind-assist-tr-image-to-text_and_QA_suitable_UnslothFinetune
https://huggingface.co/datasets/SalihHub/blind-assist-tr-image-to-text_and_QA_suitable_UnslothFinetune