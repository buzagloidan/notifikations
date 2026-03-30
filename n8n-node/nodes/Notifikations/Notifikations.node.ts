import {
	IDataObject,
	IExecuteFunctions,
	INodeExecutionData,
	INodeType,
	INodeTypeDescription,
} from 'n8n-workflow';

export class Notifikations implements INodeType {
	description: INodeTypeDescription = {
		displayName: 'Notifikations',
		name: 'notifikations',
		icon: 'file:notifikations.svg',
		group: ['output'],
		version: 1,
		subtitle: '={{$parameter["message"]}}',
		description: 'Send a push notification to your iPhone or Mac via Notifikations',
		defaults: {
			name: 'Notifikations',
		},
		inputs: ['main'],
		outputs: ['main'],
		credentials: [
			{
				name: 'notifikationsApi',
				required: true,
			},
		],
		properties: [
			{
				displayName: 'Message',
				name: 'message',
				type: 'string',
				required: true,
				default: '',
				placeholder: 'Workflow finished ✅',
				description: 'The notification body text',
			},
			{
				displayName: 'Title',
				name: 'title',
				type: 'string',
				default: '',
				description: 'Optional notification title',
			},
			{
				displayName: 'Additional Fields',
				name: 'additionalFields',
				type: 'collection',
				placeholder: 'Add Field',
				default: {},
				options: [
					{
						displayName: 'Image URL',
						name: 'image_url',
						type: 'string',
						default: '',
						description: 'URL of an image to display in the notification',
					},
					{
						displayName: 'Interruption Level',
						name: 'interruption-level',
						type: 'options',
						default: 'active',
						options: [
							{ name: 'Active', value: 'active' },
							{ name: 'Passive', value: 'passive' },
							{ name: 'Time Sensitive', value: 'time-sensitive' },
							{ name: 'Critical', value: 'critical' },
						],
						description: 'Controls how iOS presents the notification',
					},
					{
						displayName: 'Open URL',
						name: 'open_url',
						type: 'string',
						default: '',
						description: 'URL to open when the notification is tapped',
					},
					{
						displayName: 'Sound',
						name: 'sound',
						type: 'string',
						default: '',
						placeholder: 'default',
						description: 'Notification sound name',
					},
					{
						displayName: 'Subtitle',
						name: 'subtitle',
						type: 'string',
						default: '',
					},
				],
			},
		],
	};

	async execute(this: IExecuteFunctions): Promise<INodeExecutionData[][]> {
		const items = this.getInputData();
		const returnData: INodeExecutionData[] = [];

		for (let i = 0; i < items.length; i++) {
			try {
				const credentials = await this.getCredentials('notifikationsApi');
				const message = this.getNodeParameter('message', i) as string;
				const title = this.getNodeParameter('title', i) as string;
				const additionalFields = this.getNodeParameter('additionalFields', i) as IDataObject;

				const body: IDataObject = { message };
				if (title) body.title = title;
				Object.assign(body, additionalFields);

				const response = await this.helpers.httpRequest({
					method: 'POST',
					url: `https://api.notifikations.com/api/v1/${credentials.secret as string}`,
					headers: { 'Content-Type': 'application/json' },
					body,
					json: true,
				});

				returnData.push({
					json: response as IDataObject,
					pairedItem: { item: i },
				});
			} catch (error) {
				if (this.continueOnFail()) {
					returnData.push({
						json: { error: (error as Error).message },
						pairedItem: { item: i },
					});
					continue;
				}
				throw error;
			}
		}

		return [returnData];
	}
}
